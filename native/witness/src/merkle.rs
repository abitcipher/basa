use sha2::{Digest, Sha256};

pub type Hash = [u8; 32];

pub fn sha256(data: &[u8]) -> Hash {
    Sha256::digest(data).into()
}

fn leaf_hash(leaf: &Hash) -> Hash {
    let mut h = Sha256::new();
    h.update([0x00]);
    h.update(leaf);
    h.finalize().into()
}

fn node_hash(left: &Hash, right: &Hash) -> Hash {
    let mut h = Sha256::new();
    h.update([0x01]);
    h.update(left);
    h.update(right);
    h.finalize().into()
}

fn split(n: usize) -> usize {
    let mut k = 1;
    while k << 1 < n {
        k <<= 1;
    }
    k
}

pub fn root(leaves: &[Hash]) -> Option<Hash> {
    match leaves.len() {
        0 => None,
        1 => Some(leaf_hash(&leaves[0])),
        n => {
            let k = split(n);
            Some(node_hash(&root(&leaves[..k])?, &root(&leaves[k..])?))
        }
    }
}

pub fn proof(leaves: &[Hash], index: usize) -> Option<Vec<Hash>> {
    let n = leaves.len();
    if index >= n {
        return None;
    }
    if n == 1 {
        return Some(Vec::new());
    }
    let k = split(n);
    let (mut path, sibling) = if index < k {
        (proof(&leaves[..k], index)?, root(&leaves[k..])?)
    } else {
        (proof(&leaves[k..], index - k)?, root(&leaves[..k])?)
    };
    path.push(sibling);
    Some(path)
}

pub fn verify(expected: &Hash, leaf: &Hash, index: u64, size: u64, proof: &[Hash]) -> bool {
    if index >= size {
        return false;
    }
    let (mut fnode, mut snode) = (index, size - 1);
    let mut r = leaf_hash(leaf);

    for p in proof {
        if snode == 0 {
            return false;
        }
        if fnode & 1 == 1 || fnode == snode {
            r = node_hash(p, &r);
            if fnode & 1 == 0 {
                while fnode & 1 == 0 && fnode != 0 {
                    fnode >>= 1;
                    snode >>= 1;
                }
            }
        } else {
            r = node_hash(&r, p);
        }
        fnode >>= 1;
        snode >>= 1;
    }

    snode == 0 && &r == expected
}

#[cfg(test)]
mod tests {
    use super::*;

    fn leaves(n: usize) -> Vec<Hash> {
        (0..n).map(|i| sha256(&[i as u8])).collect()
    }

    #[test]
    fn every_proof_verifies_and_wrong_ones_fail() {
        for n in 1..=17 {
            let ls = leaves(n);
            let r = root(&ls).unwrap();
            for i in 0..n {
                let p = proof(&ls, i).unwrap();
                assert!(verify(&r, &ls[i], i as u64, n as u64, &p), "n={n} i={i}");
                let other = sha256(b"other");
                assert!(!verify(&r, &other, i as u64, n as u64, &p));
                if n > 1 {
                    assert!(!verify(&r, &ls[i], ((i + 1) % n) as u64, n as u64, &p));
                }
            }
        }
    }

    #[test]
    fn one_leaf_and_none() {
        assert_eq!(root(&[]), None);
        let l = sha256(b"x");
        assert_eq!(root(&[l]), Some(leaf_hash(&l)));
        assert_eq!(proof(&[l], 1), None);
    }
}
