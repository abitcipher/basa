use std::collections::BTreeMap;
use std::path::Path;

use ort::environment::Environment;
use ort::session::Session;
use ort::value::Tensor;
use serde::{Deserialize, Serialize};
use tokenizers::Tokenizer;

use crate::fetch;
use crate::manifest::{self, Nsfw};
use crate::prep;

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq)]
pub struct Phrase {
    pub key: String,
    pub text: String,
}

#[derive(Debug, Serialize, PartialEq)]
pub struct Scores {
    pub level: u8,
    pub models: Vec<String>,
    pub nsfw: f32,
    pub detectors: BTreeMap<String, f32>,
    pub clip: BTreeMap<String, f32>,
    pub ms: u128,
}

pub struct Models {
    pub level: u8,
    nsfw: Vec<(Nsfw, Session)>,
    vision: Session,
    phrases: Vec<(String, Vec<f32>)>,
}

const CLIP_SCALE: f32 = 100.0;

impl Models {
    pub fn load(
        env: &Environment,
        dir: &Path,
        level: u8,
        phrases: &[Phrase],
        mut progress: impl FnMut(u64, u64),
    ) -> Result<Models, String> {
        if !manifest::LEVELS.contains(&level) {
            return Err(format!("unknown level {level}"));
        }
        let files = manifest::files(level);
        let total = manifest::level_bytes(level);
        let mut done = 0u64;
        let mut paths = BTreeMap::new();
        for f in &files {
            let path = fetch::ensure(dir, f, |n| progress(done + n, total))?;
            done += f.bytes;
            paths.insert(f.role, path);
        }

        let session = |role: &str| -> Result<Session, String> {
            let fail = |e: &dyn std::fmt::Display| format!("cannot load {role}: {e}");
            let mut builder = Session::builder(env)
                .map_err(|e| fail(&e))?
                .with_intra_threads(2)
                .map_err(|e| fail(&e))?;
            builder.commit_from_file(&paths[role]).map_err(|e| fail(&e))
        };

        let nsfw = manifest::nsfw_models(level)
            .iter()
            .map(|m| {
                let role = match m {
                    Nsfw::Marqo => "nsfw_marqo",
                    Nsfw::Falconsai => "nsfw_falconsai",
                };
                session(role).map(|s| (*m, s))
            })
            .collect::<Result<Vec<_>, _>>()?;
        let vision = session("clip_vision")?;
        let mut text = session("clip_text")?;
        let tokenizer = Tokenizer::from_file(&paths["clip_tokenizer"])
            .map_err(|e| format!("cannot load the CLIP tokenizer: {e}"))?;

        let mut embedded = Vec::with_capacity(phrases.len());
        for p in phrases {
            embedded.push((p.key.clone(), embed_text(&mut text, &tokenizer, &p.text)?));
        }

        let mut models = Models {
            level,
            nsfw,
            vision,
            phrases: embedded,
        };
        models.self_test()?;
        Ok(models)
    }

    pub fn ids(&self) -> Vec<String> {
        let mut ids: Vec<String> = self
            .nsfw
            .iter()
            .map(|(m, _)| {
                let f = match m {
                    Nsfw::Marqo => manifest::MARQO,
                    Nsfw::Falconsai => manifest::FALCONSAI,
                };
                format!("{}@{}", m.id(), &f.sha256[..12])
            })
            .collect();
        ids.push(format!(
            "clip-vit-b32-int8@{}",
            &manifest::CLIP_VISION.sha256[..12]
        ));
        ids
    }

    pub fn check(&mut self, bytes: &[u8]) -> Result<Scores, String> {
        let started = std::time::Instant::now();
        let img = prep::decode(bytes)?;

        let mut detectors = BTreeMap::new();
        for (model, session) in self.nsfw.iter_mut() {
            let (input, name, index) = match model {
                Nsfw::Marqo => (prep::marqo(&img), "input", 0),
                Nsfw::Falconsai => (prep::falconsai(&img), "pixel_values", 1),
            };
            let logits = run_one(session, name, input, "logits")?;
            let p = prep::softmax(&logits);
            detectors.insert(model.id().to_string(), p[index]);
        }
        let nsfw = detectors.values().cloned().fold(0.0, f32::max);

        let mut clip = BTreeMap::new();
        if !self.phrases.is_empty() {
            let embeds = run_one(
                &mut self.vision,
                "pixel_values",
                prep::clip(&img),
                "image_embeds",
            )?;
            let image = prep::normalized(&embeds);
            let logits: Vec<f32> = self
                .phrases
                .iter()
                .map(|(_, t)| CLIP_SCALE * image.iter().zip(t).map(|(a, b)| a * b).sum::<f32>())
                .collect();
            for ((key, _), p) in self.phrases.iter().zip(prep::softmax(&logits)) {
                *clip.entry(key.clone()).or_insert(0.0) += p;
            }
        }

        Ok(Scores {
            level: self.level,
            models: self.ids(),
            nsfw,
            detectors,
            clip,
            ms: started.elapsed().as_millis(),
        })
    }

    fn self_test(&mut self) -> Result<(), String> {
        let img = image::RgbImage::from_pixel(64, 48, image::Rgb([128, 128, 128]));
        let mut png = Vec::new();
        image::DynamicImage::ImageRgb8(img)
            .write_to(&mut std::io::Cursor::new(&mut png), image::ImageFormat::Png)
            .map_err(|e| e.to_string())?;
        let s = self
            .check(&png)
            .map_err(|e| format!("self-test failed: {e}"))?;
        let ok = (0.0..=1.0).contains(&s.nsfw)
            && s.detectors.values().all(|p| p.is_finite())
            && s.clip.values().all(|p| p.is_finite());
        if ok {
            Ok(())
        } else {
            Err("self-test gave invalid scores".into())
        }
    }
}

fn run_one(
    session: &mut Session,
    input: &str,
    data: ndarray::Array4<f32>,
    output: &str,
) -> Result<Vec<f32>, String> {
    let tensor = Tensor::from_array(data).map_err(|e| e.to_string())?;
    let outputs = session
        .run(ort::inputs![input => tensor])
        .map_err(|e| e.to_string())?;
    let (_, values) = outputs[output]
        .try_extract_tensor::<f32>()
        .map_err(|e| e.to_string())?;
    Ok(values.to_vec())
}

fn embed_text(
    session: &mut Session,
    tokenizer: &Tokenizer,
    text: &str,
) -> Result<Vec<f32>, String> {
    let encoding = tokenizer
        .encode(text, true)
        .map_err(|e| format!("cannot read the phrase {text:?}: {e}"))?;
    let ids: Vec<i64> = encoding
        .get_ids()
        .iter()
        .take(77)
        .map(|&i| i as i64)
        .collect();
    let len = ids.len();
    let tensor = Tensor::from_array(([1usize, len], ids)).map_err(|e| e.to_string())?;
    let outputs = session
        .run(ort::inputs!["input_ids" => tensor])
        .map_err(|e| e.to_string())?;
    let (_, values) = outputs["text_embeds"]
        .try_extract_tensor::<f32>()
        .map_err(|e| e.to_string())?;
    Ok(prep::normalized(values))
}
