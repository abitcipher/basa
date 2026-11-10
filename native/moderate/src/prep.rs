use std::io::Cursor;

use image::imageops::FilterType;
use image::{DynamicImage, ImageReader, Limits, RgbImage};
use ndarray::Array4;

pub fn decode(bytes: &[u8]) -> Result<RgbImage, String> {
    let mut reader = ImageReader::new(Cursor::new(bytes))
        .with_guessed_format()
        .map_err(|e| format!("unreadable image: {e}"))?;
    let mut limits = Limits::default();
    limits.max_image_width = Some(12_000);
    limits.max_image_height = Some(12_000);
    limits.max_alloc = Some(512 * 1024 * 1024);
    reader.limits(limits);
    let img: DynamicImage = reader
        .decode()
        .map_err(|e| format!("unreadable image: {e}"))?;
    Ok(img.to_rgb8())
}

pub fn marqo(img: &RgbImage) -> Array4<f32> {
    let resized = image::imageops::resize(img, 384, 384, FilterType::CatmullRom);
    tensor(&resized, [0.5; 3], [0.5; 3])
}

pub fn falconsai(img: &RgbImage) -> Array4<f32> {
    let resized = image::imageops::resize(img, 224, 224, FilterType::Triangle);
    tensor(&resized, [0.5; 3], [0.5; 3])
}

pub fn clip(img: &RgbImage) -> Array4<f32> {
    let (w, h) = img.dimensions();
    let scale = 224.0 / w.min(h).max(1) as f32;
    let (nw, nh) = (
        ((w as f32 * scale).round() as u32).max(224),
        ((h as f32 * scale).round() as u32).max(224),
    );
    let resized = image::imageops::resize(img, nw, nh, FilterType::CatmullRom);
    let (x, y) = ((nw - 224) / 2, (nh - 224) / 2);
    let cropped = image::imageops::crop_imm(&resized, x, y, 224, 224).to_image();
    tensor(
        &cropped,
        [0.481_454_66, 0.457_827_5, 0.408_210_73],
        [0.268_629_54, 0.261_302_58, 0.275_777_11],
    )
}

fn tensor(img: &RgbImage, mean: [f32; 3], std: [f32; 3]) -> Array4<f32> {
    let (w, h) = img.dimensions();
    let mut t = Array4::<f32>::zeros((1, 3, h as usize, w as usize));
    for (x, y, p) in img.enumerate_pixels() {
        for c in 0..3 {
            t[[0, c, y as usize, x as usize]] = (p[c] as f32 / 255.0 - mean[c]) / std[c];
        }
    }
    t
}

pub fn softmax(logits: &[f32]) -> Vec<f32> {
    let max = logits.iter().cloned().fold(f32::NEG_INFINITY, f32::max);
    let exps: Vec<f32> = logits.iter().map(|l| (l - max).exp()).collect();
    let sum: f32 = exps.iter().sum();
    exps.iter().map(|e| e / sum).collect()
}

pub fn normalized(v: &[f32]) -> Vec<f32> {
    let n = v.iter().map(|x| x * x).sum::<f32>().sqrt().max(1e-12);
    v.iter().map(|x| x / n).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn png(w: u32, h: u32, rgb: [u8; 3]) -> Vec<u8> {
        let img = RgbImage::from_pixel(w, h, image::Rgb(rgb));
        let mut out = Vec::new();
        DynamicImage::ImageRgb8(img)
            .write_to(&mut Cursor::new(&mut out), image::ImageFormat::Png)
            .unwrap();
        out
    }

    #[test]
    fn inputs_have_each_models_shape_and_scale() {
        let img = decode(&png(640, 480, [255, 0, 128])).unwrap();
        let m = marqo(&img);
        assert_eq!(m.shape(), &[1, 3, 384, 384]);
        assert!((m[[0, 0, 10, 10]] - 1.0).abs() < 1e-5);
        assert!((m[[0, 1, 10, 10]] + 1.0).abs() < 1e-5);

        assert_eq!(falconsai(&img).shape(), &[1, 3, 224, 224]);

        let c = clip(&img);
        assert_eq!(c.shape(), &[1, 3, 224, 224]);
        let red = (1.0 - 0.481_454_66) / 0.268_629_54;
        assert!((c[[0, 0, 100, 100]] - red).abs() < 1e-3);
    }

    #[test]
    fn tall_and_tiny_images_still_fill_the_crop() {
        assert_eq!(
            clip(&decode(&png(30, 900, [0, 0, 0])).unwrap()).shape(),
            &[1, 3, 224, 224]
        );
        assert_eq!(
            clip(&decode(&png(1, 1, [0, 0, 0])).unwrap()).shape(),
            &[1, 3, 224, 224]
        );
    }

    #[test]
    fn junk_is_refused() {
        assert!(decode(b"not an image").is_err());
    }

    #[test]
    fn softmax_and_normalisation() {
        let p = softmax(&[0.0, 0.0]);
        assert!((p[0] - 0.5).abs() < 1e-6);
        let p = softmax(&[1000.0, 0.0]);
        assert!(p[0] > 0.999);
        let n = normalized(&[3.0, 4.0]);
        assert!((n[0] - 0.6).abs() < 1e-6 && (n[1] - 0.8).abs() < 1e-6);
    }
}
