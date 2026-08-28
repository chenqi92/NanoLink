//! GUI module for NanoOps Agent configuration wizard
//!
//! This module provides a graphical user interface for configuring
//! the NanoOps Agent when no configuration file is found.

mod wizard;

pub use wizard::run_wizard;
