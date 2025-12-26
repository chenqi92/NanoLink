//! GUI module for NanoLink Agent configuration wizard
//!
//! This module provides a graphical user interface for configuring
//! the NanoLink Agent when no configuration file is found.

mod wizard;

pub use wizard::run_wizard;
