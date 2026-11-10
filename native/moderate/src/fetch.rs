use std::fs;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};

use sha2::{Digest, Sha256};

use crate::manifest::File;

pub fn path(dir: &Path, file: &File) -> PathBuf {
    dir.join(file.sha256)
}

pub fn ensure(dir: &Path, file: &File, mut progress: impl FnMut(u64)) -> Result<PathBuf, String> {
    let target = path(dir, file);
    if target.exists() {
        if hash_file(&target)? == file.sha256 {
            progress(file.bytes);
            return Ok(target);
        }
        fs::remove_file(&target).map_err(|e| format!("cannot remove broken {}: {e}", file.role))?;
    }

    fs::create_dir_all(dir).map_err(|e| format!("cannot create the models directory: {e}"))?;
    let part = dir.join(format!("{}.part", file.sha256));
    let result = download(file, &part, &mut progress);
    if result.is_err() {
        let _ = fs::remove_file(&part);
    }
    result?;
    fs::rename(&part, &target).map_err(|e| format!("cannot keep {}: {e}", file.role))?;
    Ok(target)
}

fn download(file: &File, part: &Path, progress: &mut impl FnMut(u64)) -> Result<(), String> {
    let response = ureq::get(file.url)
        .call()
        .map_err(|e| format!("download of {} failed: {e}", file.role))?;
    let mut body = response.into_body();
    let mut reader = body.as_reader();
    let mut out = fs::File::create(part).map_err(|e| format!("cannot write {}: {e}", file.role))?;
    let mut hasher = Sha256::new();
    let mut buf = vec![0u8; 1 << 16];
    let mut got: u64 = 0;

    loop {
        let n = reader
            .read(&mut buf)
            .map_err(|e| format!("download of {} broke off: {e}", file.role))?;
        if n == 0 {
            break;
        }
        got += n as u64;
        if got > file.bytes {
            return Err(format!("{} is larger than expected", file.role));
        }
        hasher.update(&buf[..n]);
        out.write_all(&buf[..n])
            .map_err(|e| format!("cannot write {}: {e}", file.role))?;
        progress(got);
    }
    out.sync_all()
        .map_err(|e| format!("cannot write {}: {e}", file.role))?;

    let sha = hex::encode(hasher.finalize());
    if sha == file.sha256 {
        Ok(())
    } else {
        Err(format!("{} does not match its checksum", file.role))
    }
}

pub fn hash_file(path: &Path) -> Result<String, String> {
    let mut f = fs::File::open(path).map_err(|e| format!("cannot read {}: {e}", path.display()))?;
    let mut hasher = Sha256::new();
    let mut buf = vec![0u8; 1 << 16];
    loop {
        let n = f
            .read(&mut buf)
            .map_err(|e| format!("cannot read {}: {e}", path.display()))?;
        if n == 0 {
            break;
        }
        hasher.update(&buf[..n]);
    }
    Ok(hex::encode(hasher.finalize()))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tmp(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("basa-moderate-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn file_for(bytes: &[u8]) -> File {
        let sha: &'static str = Box::leak(hex::encode(Sha256::digest(bytes)).into_boxed_str());
        File {
            role: "test",
            url: "https://invalid.example/model.onnx",
            sha256: sha,
            bytes: bytes.len() as u64,
            license: "test",
        }
    }

    #[test]
    fn a_file_already_there_with_the_right_hash_is_used() {
        let dir = tmp("present");
        let file = file_for(b"weights");
        fs::write(path(&dir, &file), b"weights").unwrap();
        let mut seen = 0;
        assert_eq!(
            ensure(&dir, &file, |n| seen = n).unwrap(),
            path(&dir, &file)
        );
        assert_eq!(seen, 7);
    }

    #[test]
    fn a_broken_file_is_removed_and_fetched_again() {
        let dir = tmp("broken");
        let file = file_for(b"weights");
        fs::write(path(&dir, &file), b"tampered").unwrap();
        assert!(ensure(&dir, &file, |_| {}).is_err());
        assert!(!path(&dir, &file).exists());
        assert!(!dir.join(format!("{}.part", file.sha256)).exists());
    }
}
