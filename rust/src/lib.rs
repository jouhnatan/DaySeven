//! DaySeven's CRDT core.
//!
//! Wraps `yrs` (the Rust port of Yjs) behind a handle-based API that
//! flutter_rust_bridge exposes to Dart. Everything about the workspace document
//! shape lives in `api::workspace`.

pub mod api;
mod frb_generated;
