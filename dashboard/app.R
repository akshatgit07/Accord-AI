library(shiny)
library(httr2)
library(jsonlite)
library(plotly)
library(leaflet)

poll_interval_ms <- 5000
events_api_url <- "http://localhost:8000/events"

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

normalize_events <- function(data) {
  if (is.null(data) || nrow(data) == 0) {
    return(data.frame())
  }

  if (!"occurred_at" %in% names(data)) {
    data$occurred_at <- NA_character_
  }

  if (!"score" %in% names(data)) {
    data$score <- NA_real_
  }

  if (!"locations.lat" %in% names(data)) {
    data$locations.lat <- NA_real_
  }

  if (!"locations.lon" %in% names(data)) {
    data$locations.lon <- NA_real_
  }

  if (!"locations.name" %in% names(data)) {
    data$locations.name <- NA_character_
  }

  if (!"verification_status" %in% names(data)) {
    data$verification_status <- "unverified"
  }

  if (!"priority" %in% names(data)) {
    data$priority <- "p3"
  }

  data$occurred_at <- as.POSIXct(data$occurred_at, format = "%Y-%m-%dT%H:%M:%OSZ", tz = "UTC")
  data
}

has_coordinates <- function(data) {
  if (is.null(data) || nrow(data) == 0) {
    return(rep(FALSE, 0))
  }

  !is.na(data$locations.lat) & !is.na(data$locations.lon)
}

metric_card <- function(label, value, tone = "neutral") {
  div(
    class = paste("metric-card", paste0("metric-", tone)),
    div(class = "metric-label", label),
    div(class = "metric-value", value)
  )
}

priority_rank <- function(priority) {
  lookup <- c(p1 = 3, p2 = 2, p3 = 1)
  unname(ifelse(priority %in% names(lookup), lookup[priority], 0))
}

ui <- fluidPage(
  tags$head(
    tags$title("Accord AI Dashboard"),
    tags$style(HTML("
      :root {
        --bg: #f6efe6;
        --panel: rgba(255, 250, 244, 0.9);
        --panel-strong: #fffdf9;
        --ink: #1f2d3d;
        --muted: #6b7280;
        --accent: #bb4d00;
        --accent-soft: #ffe2c7;
        --signal: #0f766e;
        --signal-soft: #dbf5ef;
        --line: rgba(31, 45, 61, 0.10);
        --shadow: 0 18px 45px rgba(31, 45, 61, 0.12);
      }

      body {
        background:
          radial-gradient(circle at top left, rgba(255, 212, 163, 0.8), transparent 30%),
          linear-gradient(180deg, #fff7ee 0%, var(--bg) 100%);
        color: var(--ink);
        font-family: Avenir Next, Segoe UI, Helvetica Neue, sans-serif;
      }

      .container-fluid {
        max-width: 1380px;
        padding: 28px 24px 36px 24px;
      }

      .hero-shell {
        background: linear-gradient(135deg, rgba(31, 45, 61, 0.98), rgba(45, 74, 106, 0.96));
        border-radius: 26px;
        padding: 28px 30px;
        color: #fff7ef;
        box-shadow: var(--shadow);
        margin-bottom: 20px;
      }

      .hero-eyebrow {
        text-transform: uppercase;
        letter-spacing: 0.16em;
        font-size: 11px;
        color: #ffd5ae;
        margin-bottom: 10px;
      }

      .hero-title {
        font-size: 38px;
        line-height: 1.05;
        font-weight: 800;
        margin: 0 0 10px 0;
      }

      .hero-subtitle {
        max-width: 760px;
        color: rgba(255, 247, 239, 0.82);
        font-size: 15px;
        line-height: 1.6;
        margin-bottom: 0;
      }

      .status-strip {
        display: flex;
        gap: 12px;
        flex-wrap: wrap;
        margin: 20px 0 22px 0;
      }

      .status-pill {
        background: rgba(255, 255, 255, 0.68);
        border: 1px solid rgba(31, 45, 61, 0.08);
        border-radius: 999px;
        padding: 10px 14px;
        font-size: 13px;
        color: var(--ink);
      }

      .metric-grid {
        display: grid;
        grid-template-columns: repeat(4, minmax(0, 1fr));
        gap: 14px;
        margin-bottom: 18px;
      }

      .metric-card {
        border-radius: 20px;
        padding: 18px 18px 16px 18px;
        background: var(--panel);
        border: 1px solid rgba(255, 255, 255, 0.6);
        box-shadow: var(--shadow);
      }

      .metric-accent {
        background: linear-gradient(180deg, #fff8ef 0%, #ffe9d2 100%);
      }

      .metric-signal {
        background: linear-gradient(180deg, #effcf8 0%, #dcfaf2 100%);
      }

      .metric-warm {
        background: linear-gradient(180deg, #fff7ef 0%, #ffe1d5 100%);
      }

      .metric-label {
        text-transform: uppercase;
        letter-spacing: 0.12em;
        font-size: 11px;
        color: var(--muted);
        margin-bottom: 8px;
      }

      .metric-value {
        font-size: 28px;
        font-weight: 800;
        line-height: 1.05;
      }

      .dashboard-panel {
        background: var(--panel);
        border-radius: 22px;
        border: 1px solid rgba(255, 255, 255, 0.72);
        box-shadow: var(--shadow);
        padding: 18px;
        margin-bottom: 18px;
      }

      .panel-title {
        font-size: 18px;
        font-weight: 700;
        margin: 0 0 4px 0;
      }

      .panel-subtitle {
        color: var(--muted);
        font-size: 13px;
        margin-bottom: 14px;
      }

      .sidebar-card {
        background: var(--panel-strong);
        border-radius: 18px;
        border: 1px solid var(--line);
        padding: 16px;
        margin-bottom: 14px;
      }

      .sidebar-label {
        text-transform: uppercase;
        letter-spacing: 0.12em;
        font-size: 11px;
        color: var(--muted);
        margin-bottom: 8px;
      }

      .sidebar-value {
        font-size: 14px;
        line-height: 1.5;
        color: var(--ink);
      }

      .event-card {
        background: #fffdf9;
        border: 1px solid var(--line);
        border-left: 5px solid var(--accent);
        border-radius: 18px;
        padding: 16px 16px 14px 16px;
        margin-bottom: 12px;
      }

      .event-card.priority-p1 { border-left-color: #c2410c; }
      .event-card.priority-p2 { border-left-color: #f59e0b; }
      .event-card.priority-p3 { border-left-color: #64748b; }

      .event-headline {
        font-size: 16px;
        font-weight: 700;
        margin-bottom: 6px;
      }

      .event-meta {
        color: var(--muted);
        font-size: 12px;
        text-transform: uppercase;
        letter-spacing: 0.08em;
        margin-bottom: 10px;
      }

      .event-summary {
        font-size: 14px;
        line-height: 1.6;
        margin-bottom: 10px;
      }

      .event-tags {
        display: flex;
        gap: 8px;
        flex-wrap: wrap;
      }

      .event-tag {
        border-radius: 999px;
        padding: 6px 10px;
        font-size: 12px;
        font-weight: 600;
        background: var(--accent-soft);
        color: #8a3b03;
      }

      .leaflet, .js-plotly-plot {
        border-radius: 18px;
        overflow: hidden;
      }

      .form-control, .selectize-input {
        border-radius: 14px !important;
        border: 1px solid var(--line) !important;
        box-shadow: none !important;
      }

      table {
        background: transparent;
      }

      @media (max-width: 960px) {
        .metric-grid {
          grid-template-columns: repeat(2, minmax(0, 1fr));
        }
      }

      @media (max-width: 640px) {
        .metric-grid {
          grid-template-columns: 1fr;
        }

        .hero-title {
          font-size: 30px;
        }
      }
    "))
  ),
  div(
    class = "hero-shell",
    div(class = "hero-eyebrow", "Operational Intelligence Workspace"),
    div(class = "hero-title", "Accord AI Live Monitoring"),
    p(
      class = "hero-subtitle",
      "A lightweight but real analyst surface for tracking geopolitical narrative shifts, reviewing scored events, and following location-aware signals as the pipeline refreshes."
    )
  ),
  div(
    class = "status-strip",
    div(class = "status-pill", textOutput("data_source_status", inline = TRUE)),
    div(class = "status-pill", textOutput("map_status", inline = TRUE))
  ),
  uiOutput("metric_cards"),
  fluidRow(
    column(
      width = 3,
      div(
        class = "dashboard-panel",
        div(class = "panel-title", "Control Surface"),
        div(class = "panel-subtitle", "Filter the current narrative slice and keep tabs on refresh status."),
        div(
          class = "sidebar-card",
          div(class = "sidebar-label", "Narrative Filter"),
          uiOutput("narrative_ui")
        ),
        div(
          class = "sidebar-card",
          div(class = "sidebar-label", "Update Cadence"),
          div(class = "sidebar-value", sprintf("Polling every %s seconds from the API, with local JSONL fallback.", poll_interval_ms / 1000))
        ),
        div(
          class = "sidebar-card",
          div(class = "sidebar-label", "Current Read"),
          htmlOutput("selection_summary")
        )
      )
    ),
    column(
      width = 9,
      fluidRow(
        column(
          width = 7,
          div(
            class = "dashboard-panel",
            div(class = "panel-title", "Signal Map"),
            div(class = "panel-subtitle", "Leaflet markers appear immediately from seeded fallback coordinates and update as event locations improve."),
            leafletOutput("event_map", height = "430px")
          )
        ),
        column(
          width = 5,
          div(
            class = "dashboard-panel",
            div(class = "panel-title", "Risk Timeline"),
            div(class = "panel-subtitle", "Scored events over time for the selected narrative."),
            plotlyOutput("timeline", height = "430px")
          )
        )
      ),
      div(
        class = "dashboard-panel",
        div(class = "panel-title", "Event Briefs"),
        div(class = "panel-subtitle", "A readable analyst feed instead of a raw table dump."),
        uiOutput("event_cards")
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
    if (nrow(data) == 0 || is.null(input$narrative) || input$narrative == "") {
      return(data)
    }
    subset(data, narrative == input$narrative)
  })

  output$data_source_status <- renderText({
    result <- events_result()
    count <- if (is.null(result$data)) 0 else nrow(result$data)
    sprintf("Source: %s. %s events loaded.", result$source, count)
  })

  output$map_status <- renderText({
    data <- filtered_events()
    if (nrow(data) == 0) {
      return("Map idle: no events available yet.")
    }

    coordinate_rows <- sum(has_coordinates(data))
    if (coordinate_rows == 0) {
      return("Map waiting: this slice has no coordinates yet.")
    }

    sprintf("Map live: plotting %s coordinate-backed event(s).", coordinate_rows)
  })

  output$metric_cards <- renderUI({
    data <- filtered_events()
    all_data <- events()

    total_events <- nrow(all_data)
    narrative_count <- if (nrow(all_data) > 0) length(unique(all_data$narrative)) else 0
    source_count <- if (nrow(all_data) > 0 && "source" %in% names(all_data)) length(unique(all_data$source)) else 0
    top_priority <- if (nrow(data) > 0) names(sort(tapply(priority_rank(data$priority), data$priority, max), decreasing = TRUE))[1] else "none"

    div(
      class = "metric-grid",
      metric_card("Events Loaded", total_events, "accent"),
      metric_card("Active Sources", source_count, "signal"),
      metric_card("Narratives", narrative_count, "neutral"),
      metric_card("Highest Priority", toupper(top_priority), "warm")
    )
  })

  output$narrative_ui <- renderUI({
    data <- events()
    choices <- if (nrow(data) > 0) unique(data$narrative) else c()
    selected <- if (length(choices) > 0) choices[1] else NULL
    selectInput("narrative", NULL, choices = choices, selected = selected)
  })

  output$selection_summary <- renderUI({
    data <- filtered_events()
    if (nrow(data) == 0) {
      return(div(class = "sidebar-value", "No events are available for the current filter."))
    }

    latest_time <- suppressWarnings(max(data$occurred_at, na.rm = TRUE))
    latest_label <- if (is.finite(latest_time)) format(latest_time, "%b %d, %Y %H:%M UTC") else "unknown"
    verified_count <- sum(data$verification_status == "verified", na.rm = TRUE)

    div(
      class = "sidebar-value",
      HTML(sprintf(
        "<strong>%s</strong> events in focus.<br/><strong>%s</strong> verified.<br/>Latest timestamp: <strong>%s</strong>.",
        nrow(data), verified_count, latest_label
      ))
    )
  })

  output$timeline <- renderPlotly({
    data <- filtered_events()
    if (nrow(data) == 0) {
      return(plot_ly())
    }

    plot_ly(
      data = data,
      x = ~occurred_at,
      y = ~score,
      type = "scatter",
      mode = "lines+markers",
      text = ~headline,
      color = ~verification_status,
      colors = c(verified = "#0f766e", unverified = "#f59e0b", contested = "#b91c1c"),
      marker = list(size = 11, line = list(color = "#fff7ef", width = 2)),
      line = list(width = 3)
    ) |>
      layout(
        paper_bgcolor = "rgba(0,0,0,0)",
        plot_bgcolor = "rgba(255,255,255,0.65)",
        margin = list(l = 40, r = 20, t = 10, b = 40),
        xaxis = list(title = "", gridcolor = "rgba(31,45,61,0.08)"),
        yaxis = list(title = "Score", gridcolor = "rgba(31,45,61,0.08)", range = c(0, 1))
      )
  })

  output$event_map <- renderLeaflet({
    data <- filtered_events()
    map <- leaflet() |>
      addProviderTiles(providers$CartoDB.PositronNoLabels)

    if (nrow(data) == 0) {
      return(map)
    }

    coordinate_mask <- has_coordinates(data)
    if (!any(coordinate_mask)) {
      return(map)
    }

    map_data <- data[coordinate_mask, , drop = FALSE]
    colors <- c(verified = "#0f766e", unverified = "#f59e0b", contested = "#b91c1c")
    popup_text <- sprintf(
      "<strong>%s</strong><br/>%s<br/>Priority: %s<br/>Score: %.2f",
      map_data$headline,
      ifelse(is.na(map_data$locations.name), "Location pending", map_data$locations.name),
      toupper(map_data$priority),
      map_data$score
    )

    map |>
      addCircleMarkers(
        lng = map_data$locations.lon,
        lat = map_data$locations.lat,
        color = colors[map_data$verification_status],
        fillColor = colors[map_data$verification_status],
        fillOpacity = 0.92,
        radius = 8,
        stroke = TRUE,
        weight = 2,
        opacity = 1,
        popup = popup_text
      )
  })

  output$event_cards <- renderUI({
    data <- filtered_events()
    if (nrow(data) == 0) {
      return(div(class = "sidebar-value", "No events available for the selected narrative yet."))
    }

    cards <- lapply(seq_len(nrow(data)), function(idx) {
      row <- data[idx, , drop = FALSE]
      entity_tags <- if (!is.null(row$entities[[1]]) && length(row$entities[[1]]) > 0) row$entities[[1]] else c("No entities")
      location_label <- if (!is.na(row$locations.name[[1]]) && nzchar(row$locations.name[[1]])) row$locations.name[[1]] else "Location pending"

      div(
        class = paste("event-card", paste0("priority-", tolower(row$priority[[1]]))),
        div(class = "event-headline", row$headline[[1]]),
        div(
          class = "event-meta",
          sprintf(
            "%s • %s • %s • score %.2f",
            row$source[[1]],
            toupper(row$priority[[1]]),
            row$verification_status[[1]],
            row$score[[1]]
          )
        ),
        div(class = "event-summary", row$summary[[1]]),
        div(
          class = "event-tags",
          div(class = "event-tag", paste("Narrative:", row$narrative[[1]])),
          div(class = "event-tag", paste("Location:", location_label)),
          lapply(entity_tags, function(tag) div(class = "event-tag", tag))
        )
      )
    })

    do.call(tagList, cards)
  })
}

shinyApp(ui = ui, server = server)
