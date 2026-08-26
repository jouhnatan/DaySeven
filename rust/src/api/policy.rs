//! Signing and verifying the workspace ownership policy.
//!
//! `metadata/yjs/policy.json` states who owns the Knowledge Base and which
//! files are protected. It travels with the workspace — through the CRDT,
//! through a backup, through a copied folder — so by the time a client reads
//! it, it has been somewhere untrusted. A client that believed it unverified
//! would take its own instructions about who is allowed to write from a file
//! anybody could have edited.
//!
//! So the policy is signed by the Knowledge Base owner and verified before any
//! role in it is believed. The trust root for the public key is Postgres, not
//! the file: `knowledge_bases.policy_public_key` is written only by the owner
//! through an RPC, and RLS decides who may read it. That means tampering with
//! the file on disk is detectable, and tampering with the key requires already
//! having the owner's account.
//!
//! This is defence in depth, not the only defence. The server independently
//! enforces the same rules in `yjs_submit_proposal` and `yjs_resolve_proposal`,
//! because a client checking its own permissions is only ever advisory.
//!
//! The crypto lives here rather than in Dart because the bridge already
//! exists, and one implementation is easier to keep correct than two.

use ed25519_dalek::{
    Signature, Signer, SigningKey, Verifier, VerifyingKey, PUBLIC_KEY_LENGTH, SECRET_KEY_LENGTH,
    SIGNATURE_LENGTH,
};
use rand::rngs::OsRng;

/// A newly generated signing identity for a Knowledge Base owner.
pub struct PolicyKeypair {
    /// Ed25519 seed. Never leaves the owner's device, never logged, never
    /// sent to the server.
    pub secret_key: Vec<u8>,
    /// Published through `set_policy_public_key` so every member can verify.
    pub public_key: Vec<u8>,
}

/// Generates an owner signing identity from the OS entropy source.
pub fn policy_generate_keypair() -> PolicyKeypair {
    let signing = SigningKey::generate(&mut OsRng);
    PolicyKeypair {
        secret_key: signing.to_bytes().to_vec(),
        public_key: signing.verifying_key().to_bytes().to_vec(),
    }
}

/// Derives the public key from a secret, so a device holding the secret can
/// republish the key without storing it twice.
pub fn policy_public_key(secret_key: Vec<u8>) -> Result<Vec<u8>, String> {
    Ok(signing_key(&secret_key)?.verifying_key().to_bytes().to_vec())
}

/// Signs the canonical bytes of a policy document.
pub fn policy_sign(secret_key: Vec<u8>, message: Vec<u8>) -> Result<Vec<u8>, String> {
    Ok(signing_key(&secret_key)?.sign(&message).to_bytes().to_vec())
}

/// True only if `signature` is this exact `message` signed by the holder of
/// the secret behind `public_key`.
///
/// Returns `Ok(false)` for a well-formed signature that does not match, and
/// `Err` only when an input is the wrong shape — so a caller cannot confuse
/// "not verified" with "could not be checked" and treat one as the other.
pub fn policy_verify(
    public_key: Vec<u8>,
    message: Vec<u8>,
    signature: Vec<u8>,
) -> Result<bool, String> {
    if public_key.len() != PUBLIC_KEY_LENGTH {
        return Err(format!(
            "public key must be {PUBLIC_KEY_LENGTH} bytes, got {}",
            public_key.len()
        ));
    }
    if signature.len() != SIGNATURE_LENGTH {
        return Err(format!(
            "signature must be {SIGNATURE_LENGTH} bytes, got {}",
            signature.len()
        ));
    }
    let key_bytes: [u8; PUBLIC_KEY_LENGTH] = public_key
        .try_into()
        .map_err(|_| "malformed public key".to_string())?;
    let verifying =
        VerifyingKey::from_bytes(&key_bytes).map_err(|e| format!("malformed public key: {e}"))?;
    let sig_bytes: [u8; SIGNATURE_LENGTH] = signature
        .try_into()
        .map_err(|_| "malformed signature".to_string())?;
    Ok(verifying
        .verify(&message, &Signature::from_bytes(&sig_bytes))
        .is_ok())
}

fn signing_key(secret: &[u8]) -> Result<SigningKey, String> {
    if secret.len() != SECRET_KEY_LENGTH {
        return Err(format!(
            "secret key must be {SECRET_KEY_LENGTH} bytes, got {}",
            secret.len()
        ));
    }
    let bytes: [u8; SECRET_KEY_LENGTH] = secret
        .try_into()
        .map_err(|_| "malformed secret key".to_string())?;
    Ok(SigningKey::from_bytes(&bytes))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_signature_verifies_against_its_own_key() {
        let kp = policy_generate_keypair();
        let message = b"{\"owner\":\"haoyu\"}".to_vec();
        let sig = policy_sign(kp.secret_key.clone(), message.clone()).unwrap();
        assert!(policy_verify(kp.public_key, message, sig).unwrap());
    }

    #[test]
    fn a_tampered_policy_does_not_verify() {
        // The attack this exists to stop: edit the policy to make yourself an
        // owner, leave the signature alone, hope nobody checks.
        let kp = policy_generate_keypair();
        let sig = policy_sign(kp.secret_key.clone(), b"{\"owner\":\"haoyu\"}".to_vec()).unwrap();
        assert!(!policy_verify(kp.public_key, b"{\"owner\":\"mallory\"}".to_vec(), sig).unwrap());
    }

    #[test]
    fn another_members_key_cannot_sign_a_policy() {
        let owner = policy_generate_keypair();
        let member = policy_generate_keypair();
        let message = b"{\"owner\":\"mallory\"}".to_vec();
        let forged = policy_sign(member.secret_key, message.clone()).unwrap();
        assert!(!policy_verify(owner.public_key, message, forged).unwrap());
    }

    #[test]
    fn public_key_is_derivable_from_the_secret() {
        let kp = policy_generate_keypair();
        assert_eq!(policy_public_key(kp.secret_key).unwrap(), kp.public_key);
    }

    #[test]
    fn wrong_sized_inputs_are_errors_not_false() {
        // "Could not be checked" must never be silently indistinguishable from
        // "checked and failed".
        let kp = policy_generate_keypair();
        let sig = policy_sign(kp.secret_key.clone(), b"x".to_vec()).unwrap();
        assert!(policy_verify(vec![0u8; 5], b"x".to_vec(), sig.clone()).is_err());
        assert!(policy_verify(kp.public_key, b"x".to_vec(), vec![0u8; 5]).is_err());
        assert!(policy_sign(vec![0u8; 5], b"x".to_vec()).is_err());
    }

    #[test]
    fn keypairs_are_not_reused_between_calls() {
        assert_ne!(
            policy_generate_keypair().public_key,
            policy_generate_keypair().public_key
        );
    }
}
