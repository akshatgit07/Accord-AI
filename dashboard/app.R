library(shiny)
library(httr2)
library(jsonlite)
library(plotly)
library(leaflet)

poll_interval_ms <- 5000
events_api_url <- "http://localhost:8000/events"
alerts_api_url <- "http://localhost:8000/alerts"
narrative_intelligence_api_url <- "http://localhost:8000/narrative-intelligence"
compliance_api_url <- "http://localhost:8000/compliance-report"

`%||%` <- function(left, right) {
  if (is.null(left) || length(left) == 0) {
    return(right)
  }
  left
}

detect_events_file_path <- function() {
  candidates <- c(
    file.path(getwd(), "data", "events.jsonl"),
    file.path(getwd(), "..", "data", "events.jsonl")
  )
  existing <- candidates[file.exists(candidates)]
  if (length(existing) > 0) {
    return(normalizePath(existing[[1]], mustWork = FALSE))
  }
  normalizePath(candidates[[1]], mustWork = FALSE)
}

events_file_path <- detect_events_file_path()

read_events_file <- function(path = events_file_path) {
  if (!file.exists(path)) {
    return(data.frame())
  }

  lines <- readLines(path, warn = FALSE)
  lines <- lines[nzchar(trimws(lines))]
  if (length(lines) == 0) {
    return(data.frame())
  }

  records <- lapply(lines, function(line) fromJSON(line, simplifyVector = TRUE))
  data <- fromJSON(toJSON(records, auto_unbox = TRUE), flatten = TRUE)
  if (is.null(data) || length(data) == 0) {
    return(data.frame())
  }

  as.data.frame(data, stringsAsFactors = FALSE)
}

fetch_events <- function() {
  tryCatch({
    resp <- request(events_api_url) |> req_perform()
    body <- resp_body_string(resp)
    data <- fromJSON(body, flatten = TRUE)
    list(
      data = if (is.null(data) || length(data) == 0) data.frame() else as.data.frame(data, stringsAsFactors = FALSE),
      source = "API"
    )
  }, error = function(err) {
    list(
      data = read_events_file(),
      source = paste("Local file fallback:", basename(events_file_path))
    )
  })
}

fetch_alerts <- function(data_fallback = data.frame()) {
  tryCatch({
    resp <- request(alerts_api_url) |> req_perform()
    body <- resp_body_string(resp)
    data <- fromJSON(body, flatten = TRUE)
    if (is.null(data) || length(data) == 0) {
      return(summarize_alerts_from_events(data_fallback))
    }
    as.data.frame(data, stringsAsFactors = FALSE)
  }, error = function(err) {
    summarize_alerts_from_events(data_fallback)
  })
}

fetch_narrative_intelligence <- function() {
  tryCatch({
    resp <- request(narrative_intelligence_api_url) |> req_perform()
    fromJSON(resp_body_string(resp), flatten = TRUE)
  }, error = function(err) {
    list(
      clusters = data.frame(),
      propagation_edges = data.frame(),
      source_stances = data.frame()
    )
  })
}

fetch_compliance_report <- function() {
  tryCatch({
    resp <- request(compliance_api_url) |> req_perform()
    fromJSON(resp_body_string(resp), flatten = TRUE)
  }, error = function(err) {
    list(
      overall_status = "insufficient_evidence",
      confidence = 0,
      reasoning_mode = "offline",
      executive_summary = "Compliance report unavailable until the API is reachable.",
      findings = data.frame(),
      recommended_actions = c("Start the API with make api, then refresh the dashboard.")
    )
  })
}

normalize_events <- function(data) {
  if (is.null(data) || nrow(data) == 0) {
    return(data.frame())
  }

  if ("locations" %in% names(data) && (!"locations.lat" %in% names(data) || !"locations.lon" %in% names(data))) {
    parsed_locations <- lapply(data$locations, function(locations) {
      if (is.null(locations) || length(locations) == 0) {
        return(list(name = NA_character_, lat = NA_real_, lon = NA_real_))
      }

      if (is.data.frame(locations) && nrow(locations) > 0) {
        valid <- locations[!is.na(locations$lat) & !is.na(locations$lon) & !(locations$lat == 0 & locations$lon == 0), , drop = FALSE]
        row <- if (nrow(valid) > 0) valid[1, , drop = FALSE] else locations[1, , drop = FALSE]
        return(list(name = as.character(row$name[[1]]), lat = as.numeric(row$lat[[1]]), lon = as.numeric(row$lon[[1]])))
      }

      if (is.list(locations) && length(locations) > 0) {
        first <- locations[[1]]
        if (is.list(first)) {
          return(list(
            name = as.character(first$name %||% NA_character_),
            lat = as.numeric(first$lat %||% NA_real_),
            lon = as.numeric(first$lon %||% NA_real_)
          ))
        }
      }

      list(name = NA_character_, lat = NA_real_, lon = NA_real_)
    })

    data$locations.name <- vapply(parsed_locations, function(item) item$name, character(1))
    data$locations.lat <- vapply(parsed_locations, function(item) item$lat, numeric(1))
    data$locations.lon <- vapply(parsed_locations, function(item) item$lon, numeric(1))
  }

  defaults <- list(
    occurred_at = NA_character_,
    score = NA_real_,
    locations.lat = NA_real_,
    locations.lon = NA_real_,
    locations.name = NA_character_,
    verification_status = "unverified",
    priority = "p3",
    event_type = "geopolitical_signal",
    narrative = "general monitoring",
    metadata.extraction_mode = "unknown"
  )

  for (name in names(defaults)) {
    if (!name %in% names(data)) {
      data[[name]] <- defaults[[name]]
    }
  }

  if (is.list(data$occurred_at) && !inherits(data$occurred_at, "POSIXct")) {
    data$occurred_at <- vapply(
      data$occurred_at,
      function(value) {
        if (length(value) == 0) {
          return(NA_character_)
        }
        as.character(value[[1]])
      },
      character(1)
    )
  }

  if (!inherits(data$occurred_at, "POSIXct")) {
    data$occurred_at <- as.POSIXct(as.character(data$occurred_at), format = "%Y-%m-%dT%H:%M:%OSZ", tz = "UTC")
  }
  data
}

summarize_alerts_from_events <- function(data) {
  if (is.null(data) || nrow(data) == 0 || !"event_type" %in% names(data)) {
    return(data.frame())
  }

  alert_types <- c("ceasefire_violation", "propaganda_alert", "sanctions_signal")
  alert_data <- data[data$event_type %in% alert_types, , drop = FALSE]
  if (nrow(alert_data) == 0) {
    return(data.frame())
  }

  groups <- split(alert_data, alert_data$event_type)
  rows <- lapply(groups, function(group) {
    priority_order <- c(p1 = 3, p2 = 2, p3 = 1)
    priority_values <- priority_order[group$priority]
    top_priority <- names(sort(tapply(priority_values, group$priority, max), decreasing = TRUE))[1]

    data.frame(
      event_type = group$event_type[[1]],
      event_count = nrow(group),
      verified_count = sum(group$verification_status == "verified", na.rm = TRUE),
      max_score = round(max(group$score, na.rm = TRUE), 2),
      top_priority = top_priority,
      stringsAsFactors = FALSE
    )
  })

  alerts <- do.call(rbind, rows)
  alerts[order(-alerts$max_score, -alerts$event_count), , drop = FALSE]
}

has_coordinates <- function(data) {
  if (is.null(data) || nrow(data) == 0) {
    return(rep(FALSE, 0))
  }
  !is.na(data$locations.lat) & !is.na(data$locations.lon) & !(data$locations.lat == 0 & data$locations.lon == 0)
}

priority_rank <- function(priority) {
  lookup <- c(p1 = 3, p2 = 2, p3 = 1)
  unname(ifelse(priority %in% names(lookup), lookup[priority], 0))
}

event_tone <- function(event_type) {
  ifelse(
    event_type == "ceasefire_violation",
    "violation",
    ifelse(event_type == "propaganda_alert", "propaganda", ifelse(event_type == "sanctions_signal", "sanctions", "signal"))
  )
}

event_color <- function(event_type) {
  palette <- c(
    ceasefire_violation = "#ff4d55",
    propaganda_alert = "#8b5cf6",
    sanctions_signal = "#f59e0b",
    geopolitical_signal = "#22c55e"
  )
  unname(ifelse(event_type %in% names(palette), palette[event_type], "#38bdf8"))
}

format_event_time <- function(value) {
  if (length(value) == 0 || is.na(value)) {
    return("Time pending")
  }
  format(value, "%H:%M UTC")
}

format_event_date <- function(value) {
  if (length(value) == 0 || is.na(value)) {
    return("Date pending")
  }
  format(value, "%b %d, %Y")
}

kpi_card <- function(label, value, delta, tone, icon) {
  div(
    class = paste("kpi-card", paste0("tone-", tone)),
    div(class = "kpi-row",
      div(
        div(class = "kpi-label", label),
        div(class = "kpi-value", value)
      ),
      div(class = "kpi-icon", icon)
    ),
    div(class = "kpi-delta", delta),
    div(class = "kpi-spark", span(), span(), span(), span(), span(), span(), span())
  )
}

section_header <- function(title, action = NULL, action_id = NULL) {
  div(
    class = "section-head",
    h3(title),
    if (!is.null(action) && !is.null(action_id)) actionLink(action_id, action, class = "section-action"),
    if (!is.null(action) && is.null(action_id)) span(class = "section-action", action)
  )
}

ui <- fluidPage(
  tags$head(
    tags$title("AccordAI Intelligence Console"),
    tags$style(HTML("
      :root {
        --bg: #06111f;
        --nav: #050b16;
        --panel: rgba(15, 31, 49, 0.92);
        --panel-2: rgba(13, 26, 43, 0.96);
        --line: rgba(148, 163, 184, 0.16);
        --line-strong: rgba(148, 163, 184, 0.28);
        --text: #e6edf7;
        --muted: #8da2bd;
        --cyan: #22d3ee;
        --green: #22c55e;
        --amber: #f59e0b;
        --red: #ff4d55;
        --violet: #8b5cf6;
        --blue: #3b82f6;
        --shadow: 0 24px 80px rgba(0, 0, 0, 0.34);
      }

      html, body {
        background: var(--bg);
        color: var(--text);
        font-family: Avenir Next, Segoe UI, Helvetica Neue, sans-serif;
      }

      body {
        background:
          radial-gradient(circle at 78% 0%, rgba(34, 211, 238, 0.10), transparent 28%),
          radial-gradient(circle at 22% 15%, rgba(139, 92, 246, 0.12), transparent 24%),
          linear-gradient(180deg, #071426 0%, #04101d 100%);
      }

      .container-fluid {
        width: 100%;
        max-width: none;
        padding: 0;
      }

      .app-shell {
        min-height: 100vh;
        display: grid;
        grid-template-columns: 224px minmax(0, 1fr);
      }

      .sidebar {
        position: sticky;
        top: 0;
        height: 100vh;
        background: linear-gradient(180deg, rgba(5, 11, 22, 0.98), rgba(4, 10, 20, 0.98));
        border-right: 1px solid var(--line);
        padding: 18px 14px;
        overflow: auto;
      }

      .brand {
        display: flex;
        align-items: center;
        gap: 10px;
        font-size: 24px;
        font-weight: 900;
        letter-spacing: -0.04em;
        margin-bottom: 22px;
      }

      .brand-mark {
        width: 32px;
        height: 32px;
        border-radius: 10px;
        display: grid;
        place-items: center;
        color: #fff;
        background: linear-gradient(135deg, var(--violet), var(--cyan));
        box-shadow: 0 0 30px rgba(139, 92, 246, 0.45);
      }

      .brand span:last-child {
        color: var(--violet);
      }

      .nav-section {
        margin-top: 20px;
      }

      .nav-label {
        color: #70839c;
        text-transform: uppercase;
        letter-spacing: 0.14em;
        font-size: 11px;
        margin: 18px 0 8px 2px;
      }

      .nav-item {
        display: flex;
        align-items: center;
        gap: 10px;
        color: #aab8ca;
        padding: 10px 12px;
        border-radius: 12px;
        font-size: 14px;
        margin-bottom: 4px;
      }

      .nav-item.active {
        color: #d8c8ff;
        background: linear-gradient(90deg, rgba(139, 92, 246, 0.22), rgba(59, 130, 246, 0.04));
        border-left: 3px solid var(--violet);
      }

      .main {
        padding: 0 28px 28px 28px;
        overflow: hidden;
      }

      .topbar {
        height: 68px;
        display: flex;
        align-items: center;
        justify-content: space-between;
        border-bottom: 1px solid var(--line);
      }

      .top-title {
        font-size: 22px;
        color: #dbe7f6;
        letter-spacing: 0.01em;
        font-weight: 750;
      }

      .top-subtitle {
        color: var(--muted);
        font-size: 12px;
        margin-top: 4px;
      }

      .top-actions {
        display: flex;
        align-items: center;
        gap: 18px;
        color: var(--muted);
        font-size: 13px;
      }

      .live-pill {
        display: inline-flex;
        align-items: center;
        gap: 7px;
        border: 1px solid var(--line-strong);
        border-radius: 10px;
        padding: 7px 11px;
        color: #c7f9d4;
        background: rgba(15, 31, 49, 0.8);
      }

      .live-dot {
        width: 7px;
        height: 7px;
        border-radius: 50%;
        background: var(--green);
        box-shadow: 0 0 14px var(--green);
      }

      .avatar {
        width: 34px;
        height: 34px;
        border-radius: 50%;
        display: grid;
        place-items: center;
        background: linear-gradient(135deg, var(--violet), #5b21b6);
        color: white;
        font-weight: 800;
      }

      .kpi-grid {
        display: grid;
        grid-template-columns: repeat(6, minmax(0, 1fr));
        gap: 12px;
        margin: 14px 0;
      }

      .kpi-card,
      .panel {
        background: linear-gradient(145deg, rgba(17, 34, 54, 0.96), rgba(9, 22, 38, 0.94));
        border: 1px solid var(--line);
        border-radius: 14px;
        box-shadow: var(--shadow);
      }

      .kpi-card {
        min-height: 122px;
        padding: 16px;
        position: relative;
        overflow: hidden;
      }

      .kpi-card::after {
        content: '';
        position: absolute;
        inset: auto -20px -34px 30%;
        height: 80px;
        border-radius: 50%;
        opacity: 0.14;
        filter: blur(20px);
      }

      .tone-blue::after { background: var(--blue); }
      .tone-green::after { background: var(--green); }
      .tone-red::after { background: var(--red); }
      .tone-violet::after { background: var(--violet); }
      .tone-amber::after { background: var(--amber); }
      .tone-cyan::after { background: var(--cyan); }

      .kpi-row {
        display: flex;
        justify-content: space-between;
        gap: 10px;
      }

      .kpi-label {
        color: #a5b4c7;
        font-size: 13px;
        margin-bottom: 10px;
      }

      .kpi-value {
        font-size: 27px;
        line-height: 1;
        font-weight: 500;
        letter-spacing: -0.04em;
      }

      .kpi-icon {
        width: 30px;
        height: 30px;
        display: grid;
        place-items: center;
        border-radius: 50%;
        border: 1px solid currentColor;
        opacity: 0.92;
      }

      .kpi-delta {
        margin-top: 10px;
        color: #8ee6a5;
        font-size: 12px;
      }

      .kpi-spark {
        position: absolute;
        right: 14px;
        bottom: 16px;
        display: flex;
        align-items: flex-end;
        gap: 4px;
        height: 28px;
      }

      .kpi-spark span {
        width: 7px;
        border-radius: 6px 6px 0 0;
        background: currentColor;
        opacity: 0.85;
      }

      .kpi-spark span:nth-child(1) { height: 8px; }
      .kpi-spark span:nth-child(2) { height: 16px; }
      .kpi-spark span:nth-child(3) { height: 12px; }
      .kpi-spark span:nth-child(4) { height: 24px; }
      .kpi-spark span:nth-child(5) { height: 14px; }
      .kpi-spark span:nth-child(6) { height: 21px; }
      .kpi-spark span:nth-child(7) { height: 18px; }

      .tone-blue { color: var(--blue); }
      .tone-green { color: var(--green); }
      .tone-red { color: var(--red); }
      .tone-violet { color: var(--violet); }
      .tone-amber { color: var(--amber); }
      .tone-cyan { color: var(--cyan); }

      .grid-top {
        display: grid;
        grid-template-columns: minmax(680px, 1fr) minmax(340px, 0.42fr);
        gap: 12px;
      }

      .grid-bottom {
        display: grid;
        grid-template-columns: minmax(320px, 0.8fr) minmax(360px, 0.9fr) minmax(320px, 0.8fr);
        gap: 12px;
        margin-top: 12px;
      }

      .panel {
        padding: 14px;
        min-height: 180px;
      }

      .panel.map-panel {
        min-height: 590px;
      }

      .map-panel .leaflet {
        box-shadow: inset 0 0 80px rgba(34, 211, 238, 0.08);
      }

      .intel-rail {
        display: grid;
        gap: 12px;
        min-height: 590px;
      }

      .rail-panel {
        min-height: 0;
      }

      .narrative-bars {
        display: grid;
        gap: 12px;
      }

      .narrative-bar-row {
        display: grid;
        grid-template-columns: minmax(0, 1fr) 128px 42px;
        align-items: center;
        gap: 10px;
      }

      .bar-track {
        height: 7px;
        border-radius: 999px;
        background: rgba(148, 163, 184, 0.18);
        overflow: hidden;
      }

      .bar-fill {
        height: 100%;
        border-radius: 999px;
        background: linear-gradient(90deg, var(--violet), var(--cyan));
      }

      .analyst-card {
        position: relative;
        min-height: 252px;
      }

      .analyst-title {
        color: var(--cyan);
        font-size: 13px;
        font-weight: 900;
        letter-spacing: 0.08em;
        text-transform: uppercase;
      }

      .analyst-summary {
        margin: 10px 0 12px 0;
        font-size: 24px;
        letter-spacing: -0.04em;
        color: #f4f8ff;
        font-weight: 760;
      }

      .analyst-bullet {
        display: flex;
        align-items: center;
        gap: 9px;
        color: var(--muted);
        font-size: 12px;
        margin: 8px 0;
      }

      .analyst-dot {
        width: 7px;
        height: 7px;
        border-radius: 999px;
        background: var(--green);
        box-shadow: 0 0 16px currentColor;
      }

      .analyst-dot.warn {
        background: var(--red);
      }

      .report-button {
        display: inline-block;
        margin-top: 14px;
        border-radius: 13px;
        padding: 11px 14px;
        color: white !important;
        background: linear-gradient(135deg, var(--violet), #5b21b6);
        text-decoration: none !important;
        font-size: 12px;
        font-weight: 800;
        box-shadow: 0 16px 40px rgba(124, 58, 237, 0.32);
      }

      .verification-grid {
        display: grid;
        grid-template-columns: minmax(0, 1fr) auto;
        gap: 8px 12px;
        align-items: center;
      }

      .verification-event {
        font-size: 21px;
        color: #f4f8ff;
        font-weight: 800;
        letter-spacing: -0.03em;
      }

      .strength-track {
        height: 10px;
        border-radius: 999px;
        background: rgba(148, 163, 184, 0.18);
        overflow: hidden;
      }

      .strength-fill {
        height: 100%;
        border-radius: 999px;
        background: var(--green);
      }

      .section-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 10px;
        margin-bottom: 12px;
      }

      .section-head h3 {
        font-size: 17px;
        margin: 0;
        color: #eef6ff;
        font-weight: 750;
      }

      .section-action {
        color: #a78bfa;
        font-size: 12px;
        background: transparent;
        border: 0;
        padding: 0;
        text-decoration: none;
        cursor: pointer;
      }

      .section-action:hover,
      .section-action:focus {
        color: #c4b5fd;
        text-decoration: none;
      }

      .map-toolbar {
        display: flex;
        align-items: center;
        gap: 18px;
        color: #91a6bd;
        font-size: 12px;
        margin-bottom: 8px;
      }

      .legend-dot {
        display: inline-block;
        width: 8px;
        height: 8px;
        border-radius: 50%;
        margin-right: 6px;
      }

      .leaflet, .js-plotly-plot {
        border-radius: 12px;
        overflow: hidden;
      }

      .leaflet-control-attribution {
        display: none;
      }

      .violation-row,
      .alert-row,
      .source-row {
        display: grid;
        grid-template-columns: 38px minmax(0, 1fr) auto;
        gap: 12px;
        align-items: center;
        padding: 10px 8px;
        border-bottom: 1px solid var(--line);
      }

      .violation-row:last-child,
      .alert-row:last-child,
      .source-row:last-child {
        border-bottom: 0;
      }

      .row-icon {
        width: 34px;
        height: 34px;
        border-radius: 10px;
        display: grid;
        place-items: center;
        background: rgba(255, 77, 85, 0.16);
        color: var(--red);
        border: 1px solid rgba(255, 77, 85, 0.28);
      }

      .row-title {
        color: #e9f2ff;
        font-size: 13px;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }

      .row-sub {
        color: var(--muted);
        font-size: 11px;
        margin-top: 2px;
      }

      .badge {
        border-radius: 999px;
        padding: 5px 8px;
        font-size: 11px;
        font-weight: 800;
      }

      .badge-high { background: rgba(255, 77, 85, 0.18); color: #ff9ba0; }
      .badge-med { background: rgba(245, 158, 11, 0.18); color: #fbc56d; }
      .badge-low { background: rgba(34, 197, 94, 0.18); color: #8df0a6; }
      .badge-purple { background: rgba(139, 92, 246, 0.18); color: #c4b5fd; }

      .stance-pill {
        display: inline-flex;
        align-items: center;
        border-radius: 999px;
        padding: 3px 8px;
        font-size: 10px;
        font-weight: 900;
        letter-spacing: 0.06em;
        text-transform: uppercase;
      }

      .stance-iran_focus { background: rgba(239, 68, 68, 0.18); color: #fca5a5; }
      .stance-israel_focus { background: rgba(59, 130, 246, 0.18); color: #93c5fd; }
      .stance-neutral { background: rgba(34, 197, 94, 0.16); color: #86efac; }
      .stance-unclear { background: rgba(148, 163, 184, 0.18); color: #cbd5e1; }

      .modal-content {
        background: #0b1728;
        color: var(--text);
        border: 1px solid var(--line-strong);
        border-radius: 16px;
      }

      .modal-header,
      .modal-footer {
        border-color: var(--line);
      }

      .intel-table {
        width: 100%;
        border-collapse: collapse;
        font-size: 12px;
      }

      .intel-table th,
      .intel-table td {
        border-bottom: 1px solid var(--line);
        padding: 9px 8px;
        vertical-align: top;
      }

      .intel-table th {
        color: #93a4ba;
        text-transform: uppercase;
        letter-spacing: 0.08em;
        font-size: 10px;
      }

      .narrative-wrap {
        display: grid;
        grid-template-columns: 1fr;
        gap: 10px;
      }

      .source-row {
        grid-template-columns: 34px minmax(0, 1fr) 48px;
      }

      .source-logo {
        width: 30px;
        height: 30px;
        border-radius: 8px;
        display: grid;
        place-items: center;
        color: white;
        font-size: 11px;
        font-weight: 900;
        background: linear-gradient(135deg, var(--blue), var(--violet));
      }

      .trust-track {
        grid-column: 2 / 4;
        height: 5px;
        border-radius: 999px;
        background: rgba(148, 163, 184, 0.16);
        overflow: hidden;
      }

      .trust-fill {
        height: 100%;
        border-radius: 999px;
        background: linear-gradient(90deg, var(--red), var(--amber), var(--green));
      }

      .alert-row {
        grid-template-columns: 34px minmax(0, 1fr) auto;
      }

      .alert-row .row-icon {
        background: rgba(139, 92, 246, 0.16);
        color: var(--violet);
        border-color: rgba(139, 92, 246, 0.3);
      }

      .timeline-note {
        color: var(--muted);
        font-size: 12px;
        margin-top: 8px;
      }

      .report-grid {
        display: grid;
        grid-template-columns: minmax(260px, 0.75fr) minmax(0, 1.25fr);
        gap: 12px;
        margin-top: 12px;
      }

      .status-chip {
        display: inline-flex;
        align-items: center;
        border-radius: 999px;
        padding: 7px 10px;
        font-size: 11px;
        font-weight: 900;
        letter-spacing: 0.08em;
        text-transform: uppercase;
        background: rgba(245, 158, 11, 0.16);
        color: #fcd58a;
      }

      .status-likely_violation { background: rgba(255, 77, 85, 0.18); color: #ffb1b5; }
      .status-watch { background: rgba(245, 158, 11, 0.16); color: #fcd58a; }
      .status-compliant { background: rgba(34, 197, 94, 0.16); color: #9af0ad; }
      .status-insufficient_evidence { background: rgba(148, 163, 184, 0.16); color: #cbd5e1; }

      .report-score {
        font-size: 42px;
        letter-spacing: -0.06em;
        margin-top: 14px;
        color: #f8fbff;
      }

      .finding-list {
        display: grid;
        gap: 8px;
      }

      .finding-card {
        border: 1px solid var(--line);
        border-radius: 12px;
        padding: 10px;
        background: rgba(6, 17, 31, 0.42);
      }

      .finding-card .row-title {
        white-space: normal;
      }

      .form-control, .selectize-input {
        background: rgba(6, 17, 31, 0.8) !important;
        border: 1px solid var(--line-strong) !important;
        color: var(--text) !important;
        border-radius: 10px !important;
      }

      @media (max-width: 1280px) {
        .app-shell { grid-template-columns: 84px minmax(0, 1fr); }
        .brand span:not(.brand-mark), .nav-label, .nav-item span.label-text { display: none; }
        .kpi-grid { grid-template-columns: repeat(3, minmax(0, 1fr)); }
        .grid-top, .grid-bottom, .report-grid { grid-template-columns: 1fr; }
        .sidebar { padding: 18px 10px; }
        .nav-item { justify-content: center; }
      }

      @media (max-width: 760px) {
        .app-shell { display: block; }
        .sidebar { position: relative; width: 100%; height: auto; display: none; }
        .main { padding: 0 12px 20px 12px; }
        .topbar { height: auto; padding: 14px 0; align-items: flex-start; gap: 10px; }
        .top-actions { flex-wrap: wrap; justify-content: flex-end; }
        .kpi-grid { grid-template-columns: 1fr; }
      }
    "))
  ),
  div(
    class = "app-shell",
    tags$aside(
      class = "sidebar",
      div(class = "brand", span(class = "brand-mark", "A"), span("Accord"), span("AI")),
      div(class = "nav-section",
        div(class = "nav-item active", "⬡", span(class = "label-text", "Dashboard")),
        div(class = "nav-label", "Intelligence"),
        div(class = "nav-item", "⌖", span(class = "label-text", "Live Map")),
        div(class = "nav-item", "◷", span(class = "label-text", "Timeline")),
        div(class = "nav-item", "☰", span(class = "label-text", "Events")),
        div(class = "nav-item", "⚠", span(class = "label-text", "Violations")),
        div(class = "nav-item", "▣", span(class = "label-text", "Sources")),
        div(class = "nav-label", "Analytics"),
        div(class = "nav-item", "◌", span(class = "label-text", "Narratives")),
        div(class = "nav-item", "✣", span(class = "label-text", "Influence Graph")),
        div(class = "nav-item", "↗", span(class = "label-text", "Trends")),
        div(class = "nav-label", "Monitoring"),
        div(class = "nav-item", "◇", span(class = "label-text", "Compliance")),
        div(class = "nav-item", "♢", span(class = "label-text", "Alerts")),
        div(class = "nav-label", "Admin"),
        div(class = "nav-item", "⚙", span(class = "label-text", "Settings"))
      )
    ),
    tags$main(
      class = "main",
      div(
        class = "topbar",
        div(
          div(class = "top-title", "Geopolitical Intelligence Command Center"),
          div(class = "top-subtitle", "Kafka -> LLM Extraction -> Narrative Propagation -> Compliance Reasoning")
        ),
        div(
          class = "top-actions",
          div(class = "live-pill", span(class = "live-dot"), "Live"),
          textOutput("clock_text", inline = TRUE),
          textOutput("timeline_range", inline = TRUE),
          span("⌕"),
          span("⚙"),
          div(class = "avatar", "RA")
        )
      ),
      uiOutput("kpi_cards"),
      div(
        class = "grid-top",
        div(
          class = "panel map-panel",
          section_header("Live Intelligence Map", tagList(
            span(class = "legend-dot", style = "background:#22c55e;"), "Verified",
            span(class = "legend-dot", style = "background:#f59e0b;margin-left:12px;"), "Unverified",
            span(class = "legend-dot", style = "background:#ff4d55;margin-left:12px;"), "Violation",
            span(class = "legend-dot", style = "background:#8b5cf6;margin-left:12px;"), "Narrative Spike"
          )),
          div(class = "map-toolbar",
            uiOutput("event_type_filter"),
            textOutput("map_status", inline = TRUE)
          ),
          leafletOutput("event_map", height = "500px")
        ),
        div(
          class = "intel-rail",
          div(class = "panel rail-panel", section_header("Violations Feed", "View all", "view_violations"), uiOutput("recent_violations")),
          div(class = "panel rail-panel", section_header("Top Narratives", "Cluster IDs", "view_clusters"), uiOutput("top_narrative_bars")),
          div(class = "panel rail-panel", section_header("Alerts", "View all", "view_alerts"), uiOutput("alerts_panel"))
        )
      ),
      div(
        class = "grid-bottom",
        div(class = "panel analyst-card", uiOutput("ai_analyst_panel")),
        div(class = "panel", section_header("Narrative Propagation", "Time ordered", "view_propagation"), plotlyOutput("influence_network", height = "230px")),
        div(class = "panel", section_header("Verification Panel", "View details", "view_confidence"), uiOutput("verification_panel"))
      ),
      div(
        class = "report-grid",
        div(class = "panel", section_header("Compliance Reasoning", "View report", "view_compliance"), uiOutput("compliance_status")),
        div(class = "panel", section_header("Analyst Findings & Actions", "Evidence", "view_compliance_evidence"), uiOutput("compliance_findings"), uiOutput("compliance_actions"))
      ),
      div(
        class = "grid-bottom",
        div(class = "panel", section_header("Timeline", "24H"), plotlyOutput("timeline_plot", height = "230px"), textOutput("timeline_note")),
        div(class = "panel", section_header("Source Focus Detection", "View method", "view_stances"), uiOutput("source_reliability")),
        div(class = "panel", section_header("Confidence Distribution", "View details", "view_confidence"), plotlyOutput("confidence_bars", height = "230px"))
      )
    )
  )
)

server <- function(input, output, session) {
  events_result <- reactive({
    invalidateLater(poll_interval_ms, session)
    result <- fetch_events()
    result$data <- normalize_events(result$data)
    result
  })

  events <- reactive({
    result <- events_result()
    if (is.null(result$data) || nrow(result$data) == 0) {
      return(data.frame())
    }
    result$data
  })

  filtered_events <- reactive({
    data <- events()
    if (nrow(data) == 0 || is.null(input$event_type_filter) || input$event_type_filter == "all") {
      return(data)
    }
    data[data$event_type == input$event_type_filter, , drop = FALSE]
  })

  alerts <- reactive({
    invalidateLater(poll_interval_ms, session)
    fetch_alerts(events())
  })

  narrative_intelligence <- reactive({
    invalidateLater(poll_interval_ms, session)
    fetch_narrative_intelligence()
  })

  compliance_report <- reactive({
    invalidateLater(poll_interval_ms, session)
    fetch_compliance_report()
  })

  show_table_modal <- function(title, headers, rows) {
    table_head <- tags$tr(lapply(headers, tags$th))
    table_rows <- lapply(rows, function(row) {
      tags$tr(lapply(row, function(value) tags$td(as.character(value))))
    })

    showModal(modalDialog(
      title = title,
      size = "l",
      easyClose = TRUE,
      div(
        style = "max-height: 62vh; overflow:auto;",
        tags$table(class = "intel-table", tags$thead(table_head), tags$tbody(table_rows))
      ),
      footer = modalButton("Close")
    ))
  }

  observeEvent(input$view_violations, {
    data <- events()
    rows <- data[data$event_type %in% c("ceasefire_violation", "propaganda_alert"), , drop = FALSE]
    rows <- rows[order(priority_rank(rows$priority), rows$score, decreasing = TRUE), , drop = FALSE]
    show_table_modal(
      "All Violations & Propaganda Alerts",
      c("Time", "Source", "Type", "Priority", "Headline"),
      lapply(seq_len(nrow(rows)), function(idx) {
        row <- rows[idx, , drop = FALSE]
        c(format_event_time(row$occurred_at[[1]]), row$source[[1]], gsub("_", " ", row$event_type[[1]]), toupper(row$priority[[1]]), row$headline[[1]])
      })
    )
  })

  observeEvent(input$view_clusters, {
    clusters <- narrative_intelligence()$clusters
    if (is.null(clusters) || nrow(clusters) == 0) {
      return()
    }
    show_table_modal(
      "Semantic Narrative Clusters",
      c("Cluster ID", "Narrative", "Events", "Sources", "First Seen", "Propagation"),
      lapply(seq_len(nrow(clusters)), function(idx) {
        row <- clusters[idx, , drop = FALSE]
        c(row$cluster_id[[1]], row$narrative[[1]], length(row$event_ids[[1]]), row$source_count[[1]], row$first_seen[[1]] %||% "pending", row$propagation_score[[1]])
      })
    )
  })

  observeEvent(input$view_confidence, {
    data <- events()
    show_table_modal(
      "Confidence Details",
      c("Source", "Type", "Score", "Priority", "Verification", "Headline"),
      lapply(seq_len(nrow(data)), function(idx) {
        row <- data[idx, , drop = FALSE]
        c(row$source[[1]], gsub("_", " ", row$event_type[[1]]), sprintf("%.0f%%", row$score[[1]] * 100), toupper(row$priority[[1]]), row$verification_status[[1]], row$headline[[1]])
      })
    )
  })

  observeEvent(input$view_stances, {
    stances <- narrative_intelligence()$source_stances
    if (is.null(stances) || nrow(stances) == 0) {
      return()
    }
    show_table_modal(
      "Source Focus Detection",
      c("Source", "Cluster", "Narrative", "Focus", "Confidence", "Events"),
      lapply(seq_len(nrow(stances)), function(idx) {
        row <- stances[idx, , drop = FALSE]
        c(row$source[[1]], row$cluster_id[[1]], row$narrative[[1]], gsub("_", " ", row$stance[[1]]), sprintf("%.0f%%", row$confidence[[1]] * 100), row$event_count[[1]])
      })
    )
  })

  observeEvent(input$view_propagation, {
    edges <- narrative_intelligence()$propagation_edges
    if (is.null(edges) || nrow(edges) == 0) {
      return()
    }
    show_table_modal(
      "Time-Ordered Propagation Edges",
      c("Likely Earlier Source", "Later Similar Source", "Cluster", "Narrative", "Similarity", "Delta Min"),
      lapply(seq_len(nrow(edges)), function(idx) {
        row <- edges[idx, , drop = FALSE]
        c(row$from_source[[1]], row$to_source[[1]], row$cluster_id[[1]], row$narrative[[1]], row$similarity[[1]], row$time_delta_minutes[[1]] %||% "unknown")
      })
    )
  })

  observeEvent(input$view_alerts, {
    data <- alerts()
    show_table_modal(
      "Alert Summary",
      c("Event Type", "Count", "Verified", "Max Score", "Top Priority"),
      lapply(seq_len(nrow(data)), function(idx) {
        row <- data[idx, , drop = FALSE]
        c(gsub("_", " ", row$event_type[[1]]), row$event_count[[1]], row$verified_count[[1]], sprintf("%.0f%%", row$max_score[[1]] * 100), toupper(row$top_priority[[1]]))
      })
    )
  })

  show_compliance_modal <- function() {
    report <- compliance_report()
    findings <- report$findings
    if (is.null(findings) || nrow(findings) == 0) {
      findings <- data.frame(
        category = "general",
        severity = "low",
        status = report$overall_status,
        summary = report$executive_summary,
        reasoning = "No finding rows were returned.",
        stringsAsFactors = FALSE
      )
    }

    show_table_modal(
      "Compliance Reasoning Report",
      c("Category", "Severity", "Status", "Summary", "Reasoning"),
      lapply(seq_len(nrow(findings)), function(idx) {
        row <- findings[idx, , drop = FALSE]
        c(
          gsub("_", " ", row$category[[1]]),
          row$severity[[1]],
          gsub("_", " ", row$status[[1]]),
          row$summary[[1]],
          row$reasoning[[1]]
        )
      })
    )
  }

  observeEvent(input$view_compliance, show_compliance_modal())
  observeEvent(input$view_compliance_evidence, show_compliance_modal())
  observeEvent(input$view_compliance_mode, {
    report <- compliance_report()
    showModal(modalDialog(
      title = "Compliance Reasoning Mode",
      easyClose = TRUE,
      p(paste("Current mode:", report$reasoning_mode %||% "unknown")),
      p("This layer combines extracted events, verification state, narrative propagation, and alert classes into analyst-support compliance findings. It is not a legal determination."),
      footer = modalButton("Close")
    ))
  })

  output$clock_text <- renderText({
    format(Sys.time(), "%H:%M:%S UTC")
  })

  output$timeline_range <- renderText({
    data <- events()
    timed <- data[!is.na(data$occurred_at), , drop = FALSE]
    if (nrow(timed) == 0) {
      return("Timeline pending")
    }
    sprintf("%s - %s", format(min(timed$occurred_at), "%b %d, %Y %H:%M"), format(max(timed$occurred_at), "%H:%M UTC"))
  })

  output$event_type_filter <- renderUI({
    data <- events()
    choices <- if (nrow(data) > 0) sort(unique(data$event_type)) else c()
    selectInput("event_type_filter", NULL, choices = c("all", choices), selected = "all", width = "180px")
  })

  output$kpi_cards <- renderUI({
    data <- events()
    total_events <- nrow(data)
    verified_events <- sum(data$verification_status == "verified", na.rm = TRUE)
    violations <- sum(data$event_type == "ceasefire_violation", na.rm = TRUE)
    active_narratives <- if (nrow(data) > 0) length(unique(data$narrative)) else 0
    avg_confidence <- if (nrow(data) > 0) paste0(round(mean(data$score, na.rm = TRUE) * 100), "%") else "0%"
    sources <- if (nrow(data) > 0) length(unique(data$source)) else 0
    violation_score <- if (nrow(data) > 0) round(min(99, (violations / max(total_events, 1)) * 100 + mean(data$score, na.rm = TRUE) * 45)) else 0
    active_conflicts <- if (nrow(data) > 0 && "locations.name" %in% names(data)) length(unique(data$locations.name[!is.na(data$locations.name)])) else 0

    div(
      class = "kpi-grid",
      kpi_card("Active Conflicts", active_conflicts, "live theaters monitored", "cyan", "⌖"),
      kpi_card("Verified Events", verified_events, "source corroborated", "green", "✓"),
      kpi_card("Violation Score", violation_score, paste(violations, "breach signals"), "red", "△"),
      kpi_card("Narrative Volatility", active_narratives, "semantic clusters", "violet", "◌"),
      kpi_card("Confidence Index", avg_confidence, "model + verification", "amber", "◇"),
      kpi_card("Sources Online", sources, "seed + Firecrawl", "cyan", "◉")
    )
  })

  output$compliance_status <- renderUI({
    report <- compliance_report()
    status <- report$overall_status %||% "insufficient_evidence"
    confidence <- round((report$confidence %||% 0) * 100)
    div(
      div(class = paste("status-chip", paste0("status-", status)), gsub("_", " ", status)),
      div(class = "report-score", paste0(confidence, "%")),
      div(class = "row-sub", report$executive_summary %||% "No compliance report available.")
    )
  })

  output$compliance_findings <- renderUI({
    report <- compliance_report()
    findings <- report$findings
    if (is.null(findings) || nrow(findings) == 0) {
      return(div(class = "row-sub", "No compliance findings yet."))
    }

    cards <- lapply(seq_len(min(nrow(findings), 3)), function(idx) {
      row <- findings[idx, , drop = FALSE]
      severity_class <- if (row$severity[[1]] %in% c("critical", "high")) "badge-high" else if (row$severity[[1]] == "medium") "badge-med" else "badge-low"
      div(
        class = "finding-card",
        div(class = "row-title", row$summary[[1]]),
        div(class = "row-sub", paste(gsub("_", " ", row$category[[1]]), "•", gsub("_", " ", row$status[[1]]))),
        div(class = paste("badge", severity_class), toupper(row$severity[[1]]))
      )
    })
    div(class = "finding-list", cards)
  })

  output$compliance_actions <- renderUI({
    report <- compliance_report()
    actions <- report$recommended_actions
    if (is.null(actions) || length(actions) == 0) {
      return(div(class = "row-sub", "No recommended actions yet."))
    }

    rows <- lapply(seq_len(min(length(actions), 4)), function(idx) {
      div(
        class = "alert-row",
        div(class = "row-icon", "◇"),
        div(
          div(class = "row-title", actions[[idx]]),
          div(class = "row-sub", paste("reasoning mode:", report$reasoning_mode %||% "unknown"))
        ),
        div(class = "badge badge-purple", paste0("#", idx))
      )
    })
    do.call(tagList, rows)
  })

  output$map_status <- renderText({
    data <- filtered_events()
    sprintf("%s mapped / %s selected events", sum(has_coordinates(data)), nrow(data))
  })

  output$event_map <- renderLeaflet({
    data <- filtered_events()
    map <- leaflet(options = leafletOptions(zoomControl = TRUE, worldCopyJump = TRUE)) |>
      addProviderTiles(providers$Esri.WorldImagery) |>
      addProviderTiles(providers$CartoDB.PositronOnlyLabels)

    if (nrow(data) == 0 || !any(has_coordinates(data))) {
      return(map |> setView(lng = 44.0, lat = 31.5, zoom = 5))
    }

    map_data <- data[has_coordinates(data), , drop = FALSE]
    colors <- event_color(map_data$event_type)
    popup_text <- sprintf(
      "<strong>%s</strong><br/>%s<br/>%s<br/>Score %.0f%%",
      map_data$headline,
      map_data$source,
      gsub("_", " ", map_data$event_type),
      map_data$score * 100
    )

    map |>
      setView(lng = 42.5, lat = 31.7, zoom = 4) |>
      addCircleMarkers(
        lng = map_data$locations.lon,
        lat = map_data$locations.lat,
        radius = 8 + (map_data$score * 7),
        color = colors,
        fillColor = colors,
        fillOpacity = 0.88,
        opacity = 1,
        weight = 2,
        popup = popup_text
      )
  })

  output$recent_violations <- renderUI({
    data <- events()
    rows <- data[data$event_type %in% c("ceasefire_violation", "propaganda_alert"), , drop = FALSE]
    rows <- rows[order(priority_rank(rows$priority), rows$score, decreasing = TRUE), , drop = FALSE]
    if (nrow(rows) == 0) {
      return(div(class = "row-sub", "No active violation or propaganda alerts."))
    }

    items <- lapply(seq_len(min(nrow(rows), 6)), function(idx) {
      row <- rows[idx, , drop = FALSE]
      badge_class <- if (row$priority[[1]] == "p1") "badge-high" else if (row$priority[[1]] == "p2") "badge-med" else "badge-purple"
      div(
        class = "violation-row",
        div(class = "row-icon", "△"),
        div(
          div(class = "row-title", row$headline[[1]]),
          div(class = "row-sub", paste(row$source[[1]], "•", gsub("_", " ", row$event_type[[1]])))
        ),
        div(class = paste("badge", badge_class), toupper(row$priority[[1]]))
      )
    })
    do.call(tagList, items)
  })

  output$top_narrative_bars <- renderUI({
    intel <- narrative_intelligence()
    clusters <- intel$clusters
    if (is.null(clusters) || nrow(clusters) == 0) {
      return(div(class = "row-sub", "Narrative clusters will appear once events are processed."))
    }

    clusters$count <- lengths(clusters$event_ids)
    clusters <- clusters[order(-clusters$count, -clusters$propagation_score), , drop = FALSE]
    max_count <- max(clusters$count, 1)
    colors <- c("#ef4444", "#f59e0b", "#8b5cf6", "#3b82f6", "#22c55e")
    rows <- lapply(seq_len(min(nrow(clusters), 5)), function(idx) {
      row <- clusters[idx, , drop = FALSE]
      pct <- round((row$count[[1]] / max_count) * 100)
      div(
        class = "narrative-bar-row",
        div(
          div(class = "row-title", row$narrative[[1]]),
          div(class = "row-sub", paste(substr(row$cluster_id[[1]], 1, 8), "•", row$source_count[[1]], "source(s)"))
        ),
        div(class = "bar-track", div(class = "bar-fill", style = sprintf("width:%s%%;background:%s;", pct, colors[[((idx - 1) %% length(colors)) + 1]]))),
        div(class = "row-sub", paste0(pct, "%"))
      )
    })
    div(class = "narrative-bars", rows)
  })

  output$ai_analyst_panel <- renderUI({
    data <- events()
    report <- compliance_report()
    intel <- narrative_intelligence()
    verified <- sum(data$verification_status == "verified", na.rm = TRUE)
    violations <- sum(data$event_type == "ceasefire_violation", na.rm = TRUE)
    propaganda <- sum(data$event_type == "propaganda_alert", na.rm = TRUE)
    clusters <- if (!is.null(intel$clusters) && nrow(intel$clusters) > 0) nrow(intel$clusters) else 0
    status <- gsub("_", " ", report$overall_status %||% "watch")

    tagList(
      div(class = "analyst-title", "AI Analyst"),
      div(class = "analyst-summary", "Today's Summary"),
      div(class = "analyst-bullet", span(class = "analyst-dot"), paste(verified, "verified event(s) across", length(unique(data$source)), "source(s)")),
      div(class = "analyst-bullet", span(class = "analyst-dot warn"), paste(violations, "likely ceasefire violation signal(s)")),
      div(class = "analyst-bullet", span(class = "analyst-dot"), paste("Narrative shift detected across", clusters, "cluster(s)")),
      div(class = "analyst-bullet", span(class = "analyst-dot"), paste(propaganda, "propaganda/disinformation signal(s); posture:", status)),
      actionLink("view_compliance_from_ai", "Generate Intelligence Report", class = "report-button")
    )
  })

  observeEvent(input$view_compliance_from_ai, show_compliance_modal())

  output$verification_panel <- renderUI({
    data <- events()
    if (nrow(data) == 0) {
      return(div(class = "row-sub", "Verification records will appear once events are loaded."))
    }

    rows <- data[order(priority_rank(data$priority), data$score, decreasing = TRUE), , drop = FALSE]
    row <- rows[1, , drop = FALSE]
    strength <- round((row$score[[1]] %||% 0) * 100)
    source_names <- unique(data$source)
    source_items <- lapply(seq_len(min(length(source_names), 4)), function(idx) {
      source <- source_names[[idx]]
      tone <- if (idx <= 3) "color:var(--green);" else "color:var(--amber);"
      div(class = "row-sub", style = tone, paste(if (idx <= 3) "+" else "!", source))
    })

    div(
      class = "verification-grid",
      div(class = "verification-event", toupper(substr(row$headline[[1]], 1, 32))),
      div(class = "row-title", style = "color:var(--green);", paste0("Confidence: ", strength, "%")),
      div(class = "row-sub", paste(row$source[[1]], "•", gsub("_", " ", row$event_type[[1]]))),
      div(class = "badge badge-purple", toupper(row$priority[[1]])),
      div(style = "grid-column:1 / 3; display:grid; grid-template-columns:1fr 1fr; gap:6px 16px; margin-top:8px;", source_items),
      div(class = "row-sub", style = "grid-column:1 / 3; margin-top:8px;", "Verification Strength"),
      div(class = "strength-track", style = "grid-column:1 / 3;", div(class = "strength-fill", style = sprintf("width:%s%%;", strength)))
    )
  })

  output$narrative_donut <- renderPlotly({
    intel <- narrative_intelligence()
    clusters <- intel$clusters
    if (is.null(clusters) || nrow(clusters) == 0) {
      return(plot_ly())
    }
    counts <- data.frame(
      label = paste0(clusters$narrative, " / ", substr(clusters$cluster_id, 1, 8)),
      count = lengths(clusters$event_ids),
      stringsAsFactors = FALSE
    )
    plot_ly(
      counts,
      labels = ~label,
      values = ~count,
      type = "pie",
      hole = 0.58,
      marker = list(colors = c("#ef4444", "#3b82f6", "#f59e0b", "#8b5cf6", "#22c55e")),
      textinfo = "none"
    ) |>
      layout(
        paper_bgcolor = "rgba(0,0,0,0)",
        plot_bgcolor = "rgba(0,0,0,0)",
        font = list(color = "#dbeafe"),
        margin = list(l = 0, r = 0, t = 0, b = 0),
        showlegend = TRUE,
        legend = list(orientation = "v", x = 0.88, y = 0.92, font = list(size = 10))
      )
  })

  output$confidence_bars <- renderPlotly({
    data <- events()
    if (nrow(data) == 0) {
      return(plot_ly())
    }
    buckets <- cut(
      data$score,
      breaks = c(0, 0.2, 0.4, 0.6, 0.8, 1),
      labels = c("0-20%", "20-40%", "40-60%", "60-80%", "80-100%"),
      include.lowest = TRUE
    )
    counts <- as.data.frame(table(buckets), stringsAsFactors = FALSE)
    plot_ly(
      counts,
      x = ~buckets,
      y = ~Freq,
      type = "bar",
      marker = list(color = c("#ef4444", "#f97316", "#f59e0b", "#22c55e", "#10b981"))
    ) |>
      layout(
        paper_bgcolor = "rgba(0,0,0,0)",
        plot_bgcolor = "rgba(0,0,0,0)",
        font = list(color = "#dbeafe"),
        margin = list(l = 35, r = 5, t = 5, b = 35),
        xaxis = list(gridcolor = "rgba(148,163,184,0.12)", title = ""),
        yaxis = list(gridcolor = "rgba(148,163,184,0.12)", title = "")
      )
  })

  output$timeline_plot <- renderPlotly({
    data <- filtered_events()
    timed <- data[!is.na(data$occurred_at), , drop = FALSE]
    if (nrow(timed) == 0) {
      return(plot_ly())
    }
    plot_ly(
      timed,
      x = ~occurred_at,
      y = ~score,
      type = "scatter",
      mode = "markers",
      color = ~event_type,
      colors = c(
        ceasefire_violation = "#ff4d55",
        propaganda_alert = "#8b5cf6",
        sanctions_signal = "#f59e0b",
        geopolitical_signal = "#22c55e"
      ),
      marker = list(size = 11, line = list(color = "#06111f", width = 2)),
      text = ~headline
    ) |>
      layout(
        paper_bgcolor = "rgba(0,0,0,0)",
        plot_bgcolor = "rgba(0,0,0,0)",
        font = list(color = "#dbeafe"),
        margin = list(l = 40, r = 10, t = 5, b = 40),
        xaxis = list(title = "", gridcolor = "rgba(148,163,184,0.12)"),
        yaxis = list(title = "Confidence", gridcolor = "rgba(148,163,184,0.12)", range = c(0, 1)),
        legend = list(orientation = "h", x = 0, y = -0.22, font = list(size = 10))
      )
  })

  output$timeline_note <- renderText({
    data <- events()
    missing <- sum(is.na(data$occurred_at))
    timed <- data[!is.na(data$occurred_at), , drop = FALSE]
    if (nrow(timed) == 0) {
      return("No timestamped articles yet.")
    }
    sprintf(
      "Timeline: %s to %s. %s event(s) have no timestamp, including some scraped pages.",
      format(min(timed$occurred_at), "%b %d, %Y %H:%M UTC"),
      format(max(timed$occurred_at), "%H:%M UTC"),
      missing
    )
  })

  output$source_reliability <- renderUI({
    intel <- narrative_intelligence()
    stances <- intel$source_stances
    if (is.null(stances) || nrow(stances) == 0) {
      return(div(class = "row-sub", "Source stance records will appear once narrative intelligence loads."))
    }
    stance_order <- c(iran_focus = 1, israel_focus = 2, neutral = 3, unclear = 4)
    stances$stance_rank <- unname(ifelse(stances$stance %in% names(stance_order), stance_order[stances$stance], 5))
    stances <- stances[order(stances$stance_rank, -stances$confidence, stances$source), , drop = FALSE]
    rows <- lapply(seq_len(min(nrow(stances), 7)), function(idx) {
      row <- stances[idx, , drop = FALSE]
      trust <- round(row$confidence[[1]] * 100)
      stance_label <- gsub("_", " ", row$stance[[1]])
      stance_class <- paste("stance-pill", paste0("stance-", row$stance[[1]]))
      div(
        class = "source-row",
        div(class = "source-logo", substr(row$source[[1]], 1, 2)),
        div(
          div(class = "row-title", row$source[[1]]),
          div(class = "row-sub", span(class = stance_class, stance_label), " ", row$narrative[[1]], " • ", substr(row$cluster_id[[1]], 1, 8))
        ),
        div(class = "row-title", paste0(trust, "%")),
        div(class = "trust-track", div(class = "trust-fill", style = sprintf("width:%s%%;", trust)))
      )
    })
    tagList(
      div(class = "row-sub", "Focus is heuristic: it reflects entity/framing emphasis, not verified ideological bias."),
      do.call(tagList, rows)
    )
  })

  output$influence_network <- renderPlotly({
    intel <- narrative_intelligence()
    edges <- intel$propagation_edges
    if (is.null(edges) || nrow(edges) == 0) {
      return(plot_ly())
    }

    sources <- unique(c(edges$from_source, edges$to_source))
    counts <- table(factor(c(edges$from_source, edges$to_source), levels = sources))
    points <- data.frame(
      label = sources,
      x = cos(seq(0, 2 * pi, length.out = length(sources) + 1)[-1]),
      y = sin(seq(0, 2 * pi, length.out = length(sources) + 1)[-1]),
      size = as.numeric(counts) * 7 + 13,
      stringsAsFactors = FALSE
    )

    line_x <- c()
    line_y <- c()
    for (idx in seq_len(nrow(edges))) {
      from <- points[points$label == edges$from_source[[idx]], , drop = FALSE]
      to <- points[points$label == edges$to_source[[idx]], , drop = FALSE]
      if (nrow(from) == 1 && nrow(to) == 1) {
        line_x <- c(line_x, from$x[[1]], to$x[[1]], NA)
        line_y <- c(line_y, from$y[[1]], to$y[[1]], NA)
      }
    }

    plot_ly() |>
      add_trace(
        x = line_x,
        y = line_y,
        type = "scatter",
        mode = "lines",
        line = list(color = "rgba(148,163,184,0.24)", width = 1),
        hoverinfo = "none",
        showlegend = FALSE
      ) |>
      add_trace(
        data = points,
        x = ~x,
        y = ~y,
        type = "scatter",
        mode = "markers+text",
        text = ~label,
        textposition = "bottom center",
        marker = list(size = ~size, color = "#3b82f6", opacity = 0.86, line = list(color = "#0b1728", width = 2)),
        hoverinfo = "text",
        showlegend = FALSE
      ) |>
      layout(
        paper_bgcolor = "rgba(0,0,0,0)",
        plot_bgcolor = "rgba(0,0,0,0)",
        font = list(color = "#dbeafe", size = 10),
        margin = list(l = 5, r = 5, t = 5, b = 5),
        xaxis = list(visible = FALSE),
        yaxis = list(visible = FALSE),
        showlegend = FALSE
      )
  })

  output$alerts_panel <- renderUI({
    data <- alerts()
    if (nrow(data) == 0) {
      return(div(class = "row-sub", "No alert summaries yet."))
    }
    rows <- lapply(seq_len(nrow(data)), function(idx) {
      row <- data[idx, , drop = FALSE]
      div(
        class = "alert-row",
        div(class = "row-icon", "◇"),
        div(
          div(class = "row-title", gsub("_", " ", row$event_type[[1]])),
          div(class = "row-sub", sprintf("%s event(s), %s verified, max %.0f%%", row$event_count[[1]], row$verified_count[[1]], row$max_score[[1]] * 100))
        ),
        div(class = "badge badge-purple", toupper(row$top_priority[[1]]))
      )
    })
    do.call(tagList, rows)
  })
}

shinyApp(ui = ui, server = server)
