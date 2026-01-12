//! Terminal User Interface module using ratatui
//!
//! Provides a responsive, efficient metrics viewer with:
//! - Responsive layouts that adapt to terminal size
//! - Double-buffered rendering (only updates changed content)
//! - Constraint-based positioning

use crate::i18n::{Lang, t};
use anyhow::Result;
use crossterm::{
    event::{self, DisableMouseCapture, EnableMouseCapture, Event, KeyCode, KeyEventKind},
    execute,
    terminal::{EnterAlternateScreen, LeaveAlternateScreen, disable_raw_mode, enable_raw_mode},
};
use ratatui::{
    Frame, Terminal,
    backend::CrosstermBackend,
    layout::{Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Gauge, Paragraph, Row, Table, Tabs, Wrap},
};
use std::io;
use std::time::Duration;
use sysinfo::{Disks, Networks, System};

use crate::collector::GpuCollector;

/// App state for the TUI
struct App<'a> {
    tabs: Vec<&'a str>,
    current_tab: usize,
    scroll_offset: usize,
    lang: Lang,
    system: System,
    disks: Disks,
    networks: Networks,
    /// Cached GPU collector to avoid re-checking availability on every frame
    gpu_collector: GpuCollector,
}

impl<'a> App<'a> {
    fn new(lang: Lang, tabs: Vec<&'a str>) -> Self {
        Self {
            tabs,
            current_tab: 0,
            scroll_offset: 0,
            lang,
            system: System::new_all(),
            disks: Disks::new_with_refreshed_list(),
            networks: Networks::new_with_refreshed_list(),
            gpu_collector: GpuCollector::new(),
        }
    }

    fn refresh_data(&mut self) {
        self.system.refresh_all();
        self.disks.refresh(false);
        self.networks.refresh(false);
    }

    fn next_tab(&mut self) {
        self.current_tab = (self.current_tab + 1) % self.tabs.len();
        self.scroll_offset = 0;
    }

    fn prev_tab(&mut self) {
        self.current_tab = self.current_tab.saturating_sub(1);
        self.scroll_offset = 0;
    }

    fn scroll_up(&mut self) {
        self.scroll_offset = self.scroll_offset.saturating_sub(1);
    }

    fn scroll_down(&mut self, max: usize) {
        if self.scroll_offset < max {
            self.scroll_offset += 1;
        }
    }
}

/// Run the interactive realtime metrics viewer using ratatui
pub fn interactive_realtime_metrics(lang: Lang) -> Result<()> {
    // Setup terminal
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen, EnableMouseCapture)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    // Create app
    let tabs = vec![
        t("metrics.cpu_overview", lang),
        t("metrics.cpu_cores", lang),
        t("metrics.memory", lang),
        t("metrics.disk_io", lang),
        t("metrics.network", lang),
        t("metrics.gpu", lang),
        t("metrics.processes", lang),
        t("metrics.ports", lang),
    ];
    let mut app = App::new(lang, tabs);

    // Main loop
    let result = run_app(&mut terminal, &mut app);

    // Restore terminal
    disable_raw_mode()?;
    execute!(
        terminal.backend_mut(),
        LeaveAlternateScreen,
        DisableMouseCapture
    )?;
    terminal.show_cursor()?;

    result
}

fn run_app<B: ratatui::backend::Backend>(terminal: &mut Terminal<B>, app: &mut App) -> Result<()> {
    loop {
        app.refresh_data();

        terminal.draw(|f| ui(f, app))?;

        // Poll for events with timeout (allows refresh)
        // 1000ms provides good balance between responsiveness and CPU usage
        if event::poll(Duration::from_millis(1000))? {
            if let Event::Key(key) = event::read()? {
                if key.kind == KeyEventKind::Press {
                    match key.code {
                        KeyCode::Char('q') | KeyCode::Esc => return Ok(()),
                        KeyCode::Left | KeyCode::Char('h') => app.prev_tab(),
                        KeyCode::Right | KeyCode::Char('l') | KeyCode::Tab => app.next_tab(),
                        KeyCode::Up | KeyCode::Char('k') => app.scroll_up(),
                        KeyCode::Down | KeyCode::Char('j') => {
                            let max_scroll = get_max_scroll(app);
                            app.scroll_down(max_scroll);
                        }
                        _ => {}
                    }
                }
            }
        }
    }
}

fn get_max_scroll(app: &App) -> usize {
    match app.current_tab {
        1 => app.system.cpus().len().saturating_sub(16), // CPU Cores
        6 => app.system.processes().len().saturating_sub(15), // Processes
        7 => 50,                                         // Ports (estimate)
        _ => 0,
    }
}

fn ui(f: &mut Frame, app: &App) {
    let size = f.area();

    // Create main layout
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3), // Tabs
            Constraint::Length(1), // Help line
            Constraint::Min(10),   // Content
        ])
        .split(size);

    // Render tabs
    let titles: Vec<Line> = app.tabs.iter().map(|t| Line::from(*t)).collect();

    let tabs = Tabs::new(titles)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .title(format!(" {} ", t("metrics.title", app.lang))),
        )
        .select(app.current_tab)
        .style(Style::default().fg(Color::White))
        .highlight_style(
            Style::default()
                .fg(Color::Cyan)
                .add_modifier(Modifier::BOLD),
        );
    f.render_widget(tabs, chunks[0]);

    // Render help line
    let help =
        Paragraph::new(t("metrics.press_q", app.lang)).style(Style::default().fg(Color::DarkGray));
    f.render_widget(help, chunks[1]);

    // Render tab content
    match app.current_tab {
        0 => render_cpu_overview(f, app, chunks[2]),
        1 => render_cpu_cores(f, app, chunks[2]),
        2 => render_memory(f, app, chunks[2]),
        3 => render_disk(f, app, chunks[2]),
        4 => render_network(f, app, chunks[2]),
        5 => render_gpu(f, app, chunks[2]),
        6 => render_processes(f, app, chunks[2]),
        7 => render_ports(f, app, chunks[2]),
        _ => {}
    }
}

fn render_cpu_overview(f: &mut Frame, app: &App, area: Rect) {
    let cpu_usage = app.system.global_cpu_usage() as f64;
    let cores = app.system.cpus().len();

    let block = Block::default()
        .borders(Borders::ALL)
        .title(" CPU Overview ");

    let inner = block.inner(area);
    f.render_widget(block, area);

    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .margin(1)
        .constraints([
            Constraint::Length(1), // Usage text
            Constraint::Length(1), // Cores text
            Constraint::Length(2), // Gauge
            Constraint::Length(2), // Load average (Unix)
            Constraint::Min(0),
        ])
        .split(inner);

    // Usage text
    let usage_style = if cpu_usage > 90.0 {
        Style::default().fg(Color::Red).add_modifier(Modifier::BOLD)
    } else if cpu_usage > 70.0 {
        Style::default()
            .fg(Color::Yellow)
            .add_modifier(Modifier::BOLD)
    } else {
        Style::default()
            .fg(Color::Green)
            .add_modifier(Modifier::BOLD)
    };

    let usage_text = Paragraph::new(Line::from(vec![
        Span::raw(format!("{}: ", t("metrics.usage", app.lang))),
        Span::styled(format!("{cpu_usage:.1}%"), usage_style),
    ]));
    f.render_widget(usage_text, chunks[0]);

    // Cores text
    let cores_text = Paragraph::new(format!("Logical Cores: {cores}"));
    f.render_widget(cores_text, chunks[1]);

    // CPU Gauge
    let gauge_color = if cpu_usage > 90.0 {
        Color::Red
    } else if cpu_usage > 70.0 {
        Color::Yellow
    } else {
        Color::Green
    };

    let gauge = Gauge::default()
        .gauge_style(Style::default().fg(gauge_color))
        .percent(cpu_usage.min(100.0) as u16)
        .label(format!("{cpu_usage:.1}%"));
    f.render_widget(gauge, chunks[2]);

    // Load average (Unix only)
    #[cfg(unix)]
    {
        let load = System::load_average();
        let load_text = Paragraph::new(Line::from(vec![
            Span::raw("Load Average: "),
            Span::styled(format!("{:.2}", load.one), Style::default().fg(Color::Cyan)),
            Span::raw("  "),
            Span::styled(
                format!("{:.2}", load.five),
                Style::default().fg(Color::Cyan),
            ),
            Span::raw("  "),
            Span::styled(
                format!("{:.2}", load.fifteen),
                Style::default().fg(Color::Cyan),
            ),
            Span::raw("  (1m / 5m / 15m)"),
        ]));
        f.render_widget(load_text, chunks[3]);
    }
}

fn render_cpu_cores(f: &mut Frame, app: &App, area: Rect) {
    let cpus = app.system.cpus();
    let visible_rows = (area.height.saturating_sub(4)) as usize; // Account for borders and header
    let start = app
        .scroll_offset
        .min(cpus.len().saturating_sub(visible_rows));
    let end = (start + visible_rows).min(cpus.len());

    let header = Row::new(vec!["Core", "Usage", "Progress"])
        .style(Style::default().add_modifier(Modifier::BOLD))
        .height(1);

    let rows: Vec<Row> = cpus
        .iter()
        .enumerate()
        .skip(start)
        .take(end - start)
        .map(|(i, cpu)| {
            let usage = cpu.cpu_usage();
            let color = if usage > 90.0 {
                Color::Red
            } else if usage > 70.0 {
                Color::Yellow
            } else {
                Color::Green
            };

            let bar_width = 30;
            let filled = ((usage as usize) * bar_width / 100).min(bar_width);
            let bar: String = format!("[{}{}]", "█".repeat(filled), "░".repeat(bar_width - filled));

            Row::new(vec![
                format!("Core {:>2}", i),
                format!("{:>5.1}%", usage),
                bar,
            ])
            .style(Style::default().fg(color))
        })
        .collect();

    let title = if cpus.len() > visible_rows {
        format!(
            " CPU Cores ({}-{} of {}, ↑↓ to scroll) ",
            start + 1,
            end,
            cpus.len()
        )
    } else {
        format!(" CPU Cores ({} total) ", cpus.len())
    };

    let table = Table::new(
        rows,
        [
            Constraint::Length(10),
            Constraint::Length(10),
            Constraint::Min(30),
        ],
    )
    .header(header)
    .block(Block::default().borders(Borders::ALL).title(title));

    f.render_widget(table, area);
}

fn render_memory(f: &mut Frame, app: &App, area: Rect) {
    let total = app.system.total_memory();
    let used = app.system.used_memory();
    let swap_total = app.system.total_swap();
    let swap_used = app.system.used_swap();

    let mem_percent = if total > 0 {
        (used as f64 / total as f64) * 100.0
    } else {
        0.0
    };

    let block = Block::default().borders(Borders::ALL).title(" Memory ");
    let inner = block.inner(area);
    f.render_widget(block, area);

    let has_swap = swap_total > 0;
    let constraints = if has_swap {
        vec![
            Constraint::Length(1), // RAM title
            Constraint::Length(1), // RAM usage
            Constraint::Length(2), // RAM gauge
            Constraint::Length(1), // Spacing
            Constraint::Length(1), // Swap title
            Constraint::Length(1), // Swap usage
            Constraint::Length(2), // Swap gauge
            Constraint::Min(0),
        ]
    } else {
        vec![
            Constraint::Length(1), // RAM title
            Constraint::Length(1), // RAM usage
            Constraint::Length(2), // RAM gauge
            Constraint::Min(0),
        ]
    };

    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .margin(1)
        .constraints(constraints)
        .split(inner);

    // RAM
    let ram_title = Paragraph::new("RAM").style(Style::default().add_modifier(Modifier::BOLD));
    f.render_widget(ram_title, chunks[0]);

    let ram_usage = Paragraph::new(format!(
        "Used: {:.2} GB / {:.2} GB  ({:.1}%)",
        used as f64 / 1024.0 / 1024.0 / 1024.0,
        total as f64 / 1024.0 / 1024.0 / 1024.0,
        mem_percent
    ))
    .style(Style::default().fg(Color::Yellow));
    f.render_widget(ram_usage, chunks[1]);

    let mem_color = if mem_percent > 90.0 {
        Color::Red
    } else if mem_percent > 70.0 {
        Color::Yellow
    } else {
        Color::Green
    };

    let ram_gauge = Gauge::default()
        .gauge_style(Style::default().fg(mem_color))
        .percent(mem_percent.min(100.0) as u16);
    f.render_widget(ram_gauge, chunks[2]);

    // Swap
    if has_swap {
        let swap_percent = (swap_used as f64 / swap_total as f64) * 100.0;

        let swap_title =
            Paragraph::new("Swap").style(Style::default().add_modifier(Modifier::BOLD));
        f.render_widget(swap_title, chunks[4]);

        let swap_usage = Paragraph::new(format!(
            "Used: {:.2} GB / {:.2} GB  ({:.1}%)",
            swap_used as f64 / 1024.0 / 1024.0 / 1024.0,
            swap_total as f64 / 1024.0 / 1024.0 / 1024.0,
            swap_percent
        ))
        .style(Style::default().fg(Color::Yellow));
        f.render_widget(swap_usage, chunks[5]);

        let swap_color = if swap_percent > 90.0 {
            Color::Red
        } else if swap_percent > 50.0 {
            Color::Yellow
        } else {
            Color::Green
        };

        let swap_gauge = Gauge::default()
            .gauge_style(Style::default().fg(swap_color))
            .percent(swap_percent.min(100.0) as u16);
        f.render_widget(swap_gauge, chunks[6]);
    }
}

fn render_disk(f: &mut Frame, app: &App, area: Rect) {
    let disks: Vec<_> = app.disks.list().iter().collect();

    let header = Row::new(vec!["Mount", "FileSystem", "Used", "Total", "Usage"])
        .style(Style::default().add_modifier(Modifier::BOLD))
        .height(1);

    let rows: Vec<Row> = disks
        .iter()
        .map(|disk| {
            let total = disk.total_space();
            let available = disk.available_space();
            let used = total - available;
            let percent = if total > 0 {
                (used as f64 / total as f64) * 100.0
            } else {
                0.0
            };

            let color = if percent > 90.0 {
                Color::Red
            } else if percent > 80.0 {
                Color::Yellow
            } else {
                Color::Green
            };

            Row::new(vec![
                truncate_string(&disk.mount_point().display().to_string(), 15),
                truncate_string(&disk.file_system().to_string_lossy(), 10),
                format!("{:.1} GB", used as f64 / 1024.0 / 1024.0 / 1024.0),
                format!("{:.1} GB", total as f64 / 1024.0 / 1024.0 / 1024.0),
                format!("{:.1}%", percent),
            ])
            .style(Style::default().fg(color))
        })
        .collect();

    let table = Table::new(
        rows,
        [
            Constraint::Length(16),
            Constraint::Length(12),
            Constraint::Length(12),
            Constraint::Length(12),
            Constraint::Length(10),
        ],
    )
    .header(header)
    .block(
        Block::default()
            .borders(Borders::ALL)
            .title(" Disk Storage "),
    );

    f.render_widget(table, area);
}

fn render_network(f: &mut Frame, app: &App, area: Rect) {
    let header = Row::new(vec!["Interface", "Received", "Transmitted"])
        .style(Style::default().add_modifier(Modifier::BOLD))
        .height(1);

    let rows: Vec<Row> = app
        .networks
        .list()
        .iter()
        .map(|(name, data)| {
            let rx = data.received();
            let tx = data.transmitted();

            let (rx_val, rx_unit) = format_bytes(rx);
            let (tx_val, tx_unit) = format_bytes(tx);

            Row::new(vec![
                truncate_string(name, 18),
                format!("{:>8.2} {}", rx_val, rx_unit),
                format!("{:>8.2} {}", tx_val, tx_unit),
            ])
        })
        .collect();

    let table = Table::new(
        rows,
        [
            Constraint::Length(20),
            Constraint::Length(15),
            Constraint::Length(15),
        ],
    )
    .header(header)
    .block(
        Block::default()
            .borders(Borders::ALL)
            .title(" Network Interfaces "),
    );

    f.render_widget(table, area);
}

fn render_gpu(f: &mut Frame, app: &App, area: Rect) {
    // Use cached collector from App state (avoids re-checking GPU availability every frame)
    let gpus = app.gpu_collector.collect();

    let block = Block::default()
        .borders(Borders::ALL)
        .title(" GPU Information ");

    if gpus.is_empty() {
        let inner = block.inner(area);
        f.render_widget(block, area);

        let text = Paragraph::new(t("metrics.no_gpu", app.lang))
            .style(Style::default().fg(Color::DarkGray))
            .wrap(Wrap { trim: true });
        f.render_widget(text, inner);
        return;
    }

    let inner = block.inner(area);
    f.render_widget(block, area);

    let gpu_height = 5; // Lines per GPU
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints(
            gpus.iter()
                .map(|_| Constraint::Length(gpu_height))
                .chain(std::iter::once(Constraint::Min(0)))
                .collect::<Vec<_>>(),
        )
        .split(inner);

    for (idx, gpu) in gpus.iter().enumerate() {
        if idx >= chunks.len() - 1 {
            break;
        }

        let gpu_chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(1), // Name
                Constraint::Length(1), // Usage + gauge
                Constraint::Length(1), // Memory
                Constraint::Length(1), // Temp + Power
                Constraint::Min(0),
            ])
            .split(chunks[idx]);

        // Name
        let name = Paragraph::new(format!(
            "GPU {}: {}",
            gpu.index,
            truncate_string(&gpu.name, 40)
        ))
        .style(Style::default().add_modifier(Modifier::BOLD));
        f.render_widget(name, gpu_chunks[0]);

        // Usage
        let usage_color = if gpu.usage_percent > 90.0 {
            Color::Red
        } else if gpu.usage_percent > 70.0 {
            Color::Yellow
        } else {
            Color::Green
        };

        let usage = Paragraph::new(Line::from(vec![
            Span::raw(format!("{}: ", t("metrics.usage", app.lang))),
            Span::styled(
                format!("{:.1}%", gpu.usage_percent),
                Style::default().fg(usage_color),
            ),
        ]));
        f.render_widget(usage, gpu_chunks[1]);

        // Memory
        let mem_total_mb = gpu.memory_total as f64 / 1024.0 / 1024.0;
        let mem_used_mb = gpu.memory_used as f64 / 1024.0 / 1024.0;
        let mem_percent = if mem_total_mb > 0.0 {
            (mem_used_mb / mem_total_mb) * 100.0
        } else {
            0.0
        };

        let memory = Paragraph::new(format!(
            "Memory: {mem_used_mb:.0} MB / {mem_total_mb:.0} MB ({mem_percent:.1}%)"
        ))
        .style(Style::default().fg(Color::Cyan));
        f.render_widget(memory, gpu_chunks[2]);

        // Temp + Power
        let mut info_spans = Vec::new();
        if gpu.temperature > 0.0 {
            let temp_color = if gpu.temperature > 80.0 {
                Color::Red
            } else if gpu.temperature > 60.0 {
                Color::Yellow
            } else {
                Color::Green
            };
            info_spans.push(Span::raw(format!(
                "{}: ",
                t("metrics.temperature", app.lang)
            )));
            info_spans.push(Span::styled(
                format!("{:.0}°C", gpu.temperature),
                Style::default().fg(temp_color),
            ));
        }
        if gpu.power_watts > 0 {
            if !info_spans.is_empty() {
                info_spans.push(Span::raw("  "));
            }
            info_spans.push(Span::raw(format!(
                "{}: {}W / {}W",
                t("metrics.power", app.lang),
                gpu.power_watts,
                gpu.power_limit_watts
            )));
        }

        if !info_spans.is_empty() {
            let info = Paragraph::new(Line::from(info_spans));
            f.render_widget(info, gpu_chunks[3]);
        }
    }
}

fn render_processes(f: &mut Frame, app: &App, area: Rect) {
    let mut procs: Vec<_> = app.system.processes().iter().collect();
    procs.sort_by(|a, b| {
        b.1.cpu_usage()
            .partial_cmp(&a.1.cpu_usage())
            .unwrap_or(std::cmp::Ordering::Equal)
    });

    let total_mem = app.system.total_memory() as f64;
    let visible_rows = (area.height.saturating_sub(4)) as usize;
    let start = app
        .scroll_offset
        .min(procs.len().saturating_sub(visible_rows));
    let end = (start + visible_rows).min(procs.len());

    let header = Row::new(vec!["PID", "CPU%", "MEM%", "MEM(MB)", "NAME"])
        .style(Style::default().add_modifier(Modifier::BOLD))
        .height(1);

    let rows: Vec<Row> = procs
        .iter()
        .skip(start)
        .take(end - start)
        .map(|(pid, proc)| {
            let mem_percent = if total_mem > 0.0 {
                (proc.memory() as f64 / total_mem) * 100.0
            } else {
                0.0
            };

            let cpu_color = if proc.cpu_usage() > 50.0 {
                Color::Red
            } else if proc.cpu_usage() > 10.0 {
                Color::Yellow
            } else {
                Color::White
            };

            Row::new(vec![
                format!("{:>7}", pid.as_u32()),
                format!("{:>6.1}%", proc.cpu_usage()),
                format!("{:>6.1}%", mem_percent),
                format!("{:>10.1}", proc.memory() as f64 / 1024.0 / 1024.0),
                truncate_string(&proc.name().to_string_lossy(), 24),
            ])
            .style(Style::default().fg(cpu_color))
        })
        .collect();

    let title = if procs.len() > visible_rows {
        format!(
            " Top Processes ({}-{} of {}, ↑↓ to scroll) ",
            start + 1,
            end,
            procs.len()
        )
    } else {
        format!(" Top Processes ({} total) ", procs.len())
    };

    let table = Table::new(
        rows,
        [
            Constraint::Length(8),
            Constraint::Length(8),
            Constraint::Length(8),
            Constraint::Length(12),
            Constraint::Min(20),
        ],
    )
    .header(header)
    .block(Block::default().borders(Borders::ALL).title(title));

    f.render_widget(table, area);
}

fn render_ports(f: &mut Frame, app: &App, area: Rect) {
    let ports = get_listening_ports();
    let visible_rows = (area.height.saturating_sub(4)) as usize;
    let start = app
        .scroll_offset
        .min(ports.len().saturating_sub(visible_rows));
    let end = (start + visible_rows).min(ports.len());

    let header = Row::new(vec!["PID", "Protocol", "Address", "Process"])
        .style(Style::default().add_modifier(Modifier::BOLD))
        .height(1);

    let rows: Vec<Row> = ports
        .iter()
        .skip(start)
        .take(end - start)
        .map(|(pid, proto, addr, name)| {
            let proto_color = if proto.contains("TCP") {
                Color::Green
            } else {
                Color::Cyan
            };

            Row::new(vec![
                pid.clone(),
                proto.clone(),
                truncate_string(addr, 22),
                truncate_string(name, 18),
            ])
            .style(Style::default().fg(proto_color))
        })
        .collect();

    let title = if ports.len() > visible_rows {
        format!(
            " Listening Ports ({}-{} of {}, ↑↓ to scroll) ",
            start + 1,
            end,
            ports.len()
        )
    } else {
        format!(" Listening Ports ({} total) ", ports.len())
    };

    let table = Table::new(
        rows,
        [
            Constraint::Length(8),
            Constraint::Length(10),
            Constraint::Length(24),
            Constraint::Min(18),
        ],
    )
    .header(header)
    .block(Block::default().borders(Borders::ALL).title(title));

    f.render_widget(table, area);
}

// Helper functions

fn truncate_string(s: &str, max_len: usize) -> String {
    if s.len() <= max_len {
        s.to_string()
    } else if max_len > 3 {
        format!("{}...", &s[..max_len - 3])
    } else {
        s[..max_len].to_string()
    }
}

fn format_bytes(bytes: u64) -> (f64, &'static str) {
    const KB: f64 = 1024.0;
    const MB: f64 = KB * 1024.0;
    const GB: f64 = MB * 1024.0;
    const TB: f64 = GB * 1024.0;

    let bytes_f = bytes as f64;

    if bytes_f >= TB {
        (bytes_f / TB, "TB")
    } else if bytes_f >= GB {
        (bytes_f / GB, "GB")
    } else if bytes_f >= MB {
        (bytes_f / MB, "MB")
    } else if bytes_f >= KB {
        (bytes_f / KB, "KB")
    } else {
        (bytes_f, "B")
    }
}

/// Get listening ports (platform-specific)
fn get_listening_ports() -> Vec<(String, String, String, String)> {
    let mut ports = Vec::new();

    #[cfg(target_os = "linux")]
    {
        use std::process::Command;
        if let Ok(output) = Command::new("ss").args(["-tulnp"]).output() {
            let stdout = String::from_utf8_lossy(&output.stdout);
            for line in stdout.lines().skip(1) {
                let parts: Vec<&str> = line.split_whitespace().collect();
                if parts.len() >= 5 {
                    let proto = parts[0].to_string();
                    let addr = parts[4].to_string();
                    let process_info = parts.get(6).unwrap_or(&"").to_string();

                    let (pid, name) = if let Some(start) = process_info.find("pid=") {
                        let pid_part = &process_info[start + 4..];
                        let pid: String = pid_part.chars().take_while(|c| c.is_numeric()).collect();
                        let name = process_info
                            .split("((\"")
                            .nth(1)
                            .and_then(|s| s.split('"').next())
                            .unwrap_or("-")
                            .to_string();
                        (pid, name)
                    } else {
                        ("-".to_string(), "-".to_string())
                    };

                    ports.push((pid, proto, addr, name));
                }
            }
        }
    }

    #[cfg(target_os = "windows")]
    {
        use std::process::Command;
        if let Ok(output) = Command::new("netstat").args(["-ano"]).output() {
            let stdout = String::from_utf8_lossy(&output.stdout);
            for line in stdout.lines() {
                if line.contains("LISTENING") {
                    let parts: Vec<&str> = line.split_whitespace().collect();
                    if parts.len() >= 5 {
                        let proto = parts[0].to_string();
                        let addr = parts[1].to_string();
                        let pid = parts[4].to_string();
                        ports.push((pid, proto, addr, "-".to_string()));
                    }
                }
            }
        }
    }

    #[cfg(target_os = "macos")]
    {
        use std::process::Command;
        if let Ok(output) = Command::new("lsof")
            .args(["-iTCP", "-sTCP:LISTEN", "-n", "-P"])
            .output()
        {
            let stdout = String::from_utf8_lossy(&output.stdout);
            for line in stdout.lines().skip(1) {
                let parts: Vec<&str> = line.split_whitespace().collect();
                if parts.len() >= 9 {
                    let name = parts[0].to_string();
                    let pid = parts[1].to_string();
                    let addr = parts.get(8).unwrap_or(&"").to_string();
                    ports.push((pid, "TCP".to_string(), addr, name));
                }
            }
        }
    }

    ports
}
