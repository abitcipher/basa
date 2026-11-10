#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct File {
    pub role: &'static str,
    pub url: &'static str,
    pub sha256: &'static str,
    pub bytes: u64,
    pub license: &'static str,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Nsfw {
    Marqo,
    Falconsai,
}

impl Nsfw {
    pub fn id(self) -> &'static str {
        match self {
            Nsfw::Marqo => "marqo-nsfw-384",
            Nsfw::Falconsai => "falconsai-nsfw-int8",
        }
    }
}

pub const MARQO: File = File {
    role: "nsfw_marqo",
    url: "https://huggingface.co/KanariKanaru/nsfw-image-detection-384-onnx/resolve/8edc47eedf74b30fd379673bc202fe3b754b1538/model.onnx",
    sha256: "e9350e576608afe4b57a089ffeb0ebafa1389cdcea4882dd61df28c45f1c24d2",
    bytes: 22_450_633,
    license: "Apache-2.0",
};

pub const FALCONSAI: File = File {
    role: "nsfw_falconsai",
    url: "https://huggingface.co/onnx-community/nsfw_image_detection-ONNX/resolve/1ceb3c7fe1e9f3f2507e6df577437f23a9149fd5/onnx/model_quantized.onnx",
    sha256: "d9afb1e057104e6cc8616d174f0f6a8b8b0389c839eea7d5efa4bdf1a77efd27",
    bytes: 87_333_629,
    license: "Apache-2.0",
};

pub const CLIP_VISION: File = File {
    role: "clip_vision",
    url: "https://huggingface.co/Xenova/clip-vit-base-patch32/resolve/6b7c523703ae26e39be4b03774966f8571c7f523/onnx/vision_model_quantized.onnx",
    sha256: "583fd1110a514667812fee7d684952aaf82a99b959760c8d7dca7e0ab9839299",
    bytes: 89_117_001,
    license: "MIT",
};

pub const CLIP_TEXT: File = File {
    role: "clip_text",
    url: "https://huggingface.co/Xenova/clip-vit-base-patch32/resolve/6b7c523703ae26e39be4b03774966f8571c7f523/onnx/text_model_quantized.onnx",
    sha256: "73baab855d406190da9faa498cfedf65f15cf309f4cc7385b7b032e6d08e5c3a",
    bytes: 64_504_507,
    license: "MIT",
};

pub const CLIP_TOKENIZER: File = File {
    role: "clip_tokenizer",
    url: "https://huggingface.co/Xenova/clip-vit-base-patch32/resolve/6b7c523703ae26e39be4b03774966f8571c7f523/tokenizer.json",
    sha256: "f7f3b7af117d467b58374797691a6438d3e6b9e9cef800dfd5dced7f697a90cd",
    bytes: 2_224_119,
    license: "MIT",
};

pub const LEVELS: [u8; 2] = [1, 2];

pub fn nsfw_models(level: u8) -> &'static [Nsfw] {
    match level {
        2 => &[Nsfw::Marqo, Nsfw::Falconsai],
        _ => &[Nsfw::Marqo],
    }
}

pub fn files(level: u8) -> Vec<File> {
    let mut files: Vec<File> = nsfw_models(level)
        .iter()
        .map(|m| match m {
            Nsfw::Marqo => MARQO,
            Nsfw::Falconsai => FALCONSAI,
        })
        .collect();
    files.extend([CLIP_VISION, CLIP_TEXT, CLIP_TOKENIZER]);
    files
}

pub fn level_bytes(level: u8) -> u64 {
    files(level).iter().map(|f| f.bytes).sum()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_file_is_pinned_and_checked() {
        for level in LEVELS {
            for f in files(level) {
                assert!(f.url.starts_with("https://huggingface.co/"), "{}", f.url);
                let rev = f
                    .url
                    .split("/resolve/")
                    .nth(1)
                    .unwrap()
                    .split('/')
                    .next()
                    .unwrap();
                assert_eq!(rev.len(), 40, "{}", f.url);
                assert!(rev.chars().all(|c| c.is_ascii_hexdigit()));
                assert_eq!(f.sha256.len(), 64);
                assert!(f.sha256.chars().all(|c| c.is_ascii_hexdigit()));
                assert!(f.bytes > 0);
            }
        }
    }

    #[test]
    fn level_2_adds_the_second_nudity_model() {
        assert_eq!(nsfw_models(1), &[Nsfw::Marqo]);
        assert_eq!(nsfw_models(2), &[Nsfw::Marqo, Nsfw::Falconsai]);
        assert!(level_bytes(1) < 200_000_000);
        assert!(level_bytes(2) < 300_000_000);
    }
}
