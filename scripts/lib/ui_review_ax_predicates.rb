#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "ui_review_contract"
require "set"

module ViftyUIReview
  # A verifier-owned implementation of the bounded AX predicate catalog. The
  # collector's sealed assertion is useful evidence, but it is not an
  # authority: release-facing verification recomputes every predicate from the
  # immutable raw observations with this implementation.
  module AXPredicates
    RAW_SCHEMA_ID = "https://vifty.app/schemas/ui-review-ax-raw-capture-v1.schema.json"
    INT32_RANGE = (-(2**31))..((2**31) - 1)
    INT64_RANGE = (-(2**63))..((2**63) - 1)
    UINT64_RANGE = 0..((2**64) - 1)

    ID = {
      control_session: "vifty.ax.control-session",
      control_session_title: "vifty.ax.control-session.title",
      control_session_summary: "vifty.ax.control-session.summary",
      fan_status: "vifty.ax.fan-status",
      left_fan_draft_target: "vifty.ax.fan-status.fan-0.draft-target",
      right_fan_draft_target: "vifty.ax.fan-status.fan-1.draft-target",
      curve_chart: "vifty.ax.curve.chart",
      curve_separate_fans: "vifty.ax.curve.separate-fans",
      curve_effective_summaries: "vifty.ax.curve.effective-summaries",
      left_fan_effective_summary: "vifty.ax.curve.fan-0.effective-summary",
      right_fan_effective_summary: "vifty.ax.curve.fan-1.effective-summary",
      curve_start_temperature: "vifty.ax.curve.start.temperature",
      curve_start_rpm: "vifty.ax.curve.start.rpm",
      curve_ramp_temperature: "vifty.ax.curve.ramp.temperature",
      curve_ramp_rpm: "vifty.ax.curve.ramp.rpm",
      curve_high_temperature: "vifty.ax.curve.high.temperature",
      curve_high_rpm: "vifty.ax.curve.high.rpm",
      sensor_list: "vifty.ax.sensors",
      sensor_cpu: "vifty.ax.sensor.cpu-efficiency",
      sensor_gpu: "vifty.ax.sensor.gpu-hotspot",
      sensor_palm: "vifty.ax.sensor.palm",
      temperature_metrics: "vifty.ax.temperature.metrics",
      curve_sensor_metric: "vifty.ax.temperature.curve-sensor",
      highest_temperature_metric: "vifty.ax.temperature.highest",
      notifications: "vifty.ax.notifications",
      notification_open_settings: "vifty.ax.notifications.open-settings",
      notification_send_test: "vifty.ax.notifications.send-test",
      notification_helper_failure: "vifty.ax.notifications.event.helper-failure",
      notification_thermal_pressure: "vifty.ax.notifications.event.high-thermal-pressure",
      notification_auto_restore: "vifty.ax.notifications.event.auto-restore-failure",
      notification_battery_drain: "vifty.ax.notifications.event.plugged-in-battery-drain",
      notification_agent_cooling: "vifty.ax.notifications.event.agent-cooling-attention",
      settings: "vifty.ax.settings",
      settings_tabs: "vifty.ax.settings.tabs",
      settings_tab_general: "vifty.ax.settings.tab.general",
      settings_tab_menu_bar: "vifty.ax.settings.tab.menu-bar",
      settings_tab_notifications: "vifty.ax.settings.tab.notifications",
      settings_tab_agent_workflows: "vifty.ax.settings.tab.agent-workflows",
      settings_pane_general: "vifty.ax.settings.pane.general",
      main_scroll: "vifty.ax.scroll.main",
      main_scroll_end: "vifty.ax.scroll.main.end",
      settings_general_scroll: "vifty.ax.scroll.settings.general",
      settings_general_scroll_end: "vifty.ax.scroll.settings.general.end",
      settings_menu_bar_scroll: "vifty.ax.scroll.settings.menu-bar",
      settings_menu_bar_scroll_end: "vifty.ax.scroll.settings.menu-bar.end",
      settings_notifications_scroll: "vifty.ax.scroll.settings.notifications",
      settings_notifications_scroll_end: "vifty.ax.scroll.settings.notifications.end",
      settings_agent_workflows_scroll: "vifty.ax.scroll.settings.agent-workflows",
      settings_agent_workflows_scroll_end: "vifty.ax.scroll.settings.agent-workflows.end"
    }.freeze

    CURVE_CONTROLS = [
      [ID[:curve_start_temperature], "Start temperature", "55 °C"],
      [ID[:curve_start_rpm], "Start RPM", "1200 RPM"],
      [ID[:curve_ramp_temperature], "Ramp temperature", "70 °C"],
      [ID[:curve_ramp_rpm], "Ramp RPM", "3500 RPM"],
      [ID[:curve_high_temperature], "High temperature", "85 °C"],
      [ID[:curve_high_rpm], "High RPM", "6200 RPM"]
    ].freeze

    EFFECTIVE_CURVE_SUMMARIES = [
      [
        ID[:left_fan_effective_summary],
        "Left Fan effective curve",
        "Start 55 °C, 1700 RPM; Ramp 70 °C, 3400 RPM; High 85 °C, 5700 RPM"
      ],
      [
        ID[:right_fan_effective_summary],
        "Right Fan effective curve",
        "Start 55 °C, 2100 RPM; Ramp 70 °C, 4200 RPM; High 85 °C, 6400 RPM"
      ]
    ].freeze

    SCROLL_CONTRACTS = {
      "compact-main-scroll-reachable" => [ID[:main_scroll], ID[:main_scroll_end]],
      "settings-general-scroll-reachable" => [ID[:settings_general_scroll], ID[:settings_general_scroll_end], true],
      "settings-menu-bar-scroll-reachable" => [ID[:settings_menu_bar_scroll], ID[:settings_menu_bar_scroll_end], true],
      "settings-notifications-scroll-reachable" => [ID[:settings_notifications_scroll], ID[:settings_notifications_scroll_end], true],
      "settings-agent-workflows-scroll-reachable" => [ID[:settings_agent_workflows_scroll], ID[:settings_agent_workflows_scroll_end], true]
    }.freeze

    module_function

    def evaluate(id, capture)
      expected_request = EXPECTED_AX_REQUESTS[id]
      return failed_assertion(id, ["unknown AX predicate"]) unless expected_request
      return failed_assertion(id, ["raw capture must be a JSON object"]) unless capture.is_a?(Hash)

      failures = []
      paths = []
      validate_capture_contract(id, expected_request, capture, failures)
      case id
      when "confirmed-owner-headline"
        validate_owner(capture, paths, failures)
      when "correct-per-fan-target"
        validate_fan_targets(capture, paths, failures)
      when "six-adjustable-point-controls"
        validate_separate_fan_curves_toggle(capture, paths, failures)
        validate_curve_controls(capture, paths, failures)
        validate_effective_curve_summaries(capture, paths, failures)
        validate_no_duplicate_chart_elements(capture, failures)
      when "no-duplicate-chart-elements"
        validate_curve_controls(capture, paths, failures)
        validate_no_duplicate_chart_elements(capture, failures)
      when "sensor-selected-trait-value"
        validate_sensors(capture, paths, failures)
      when "explicit-temperature-role"
        validate_temperature_roles(capture, paths, failures)
      when "notification-actions"
        validate_notifications(capture, paths, failures)
      when "settings-logical-traversal"
        validate_settings_traversal(capture, paths, failures)
      else
        contract = SCROLL_CONTRACTS[id]
        validate_scroll(capture, contract, paths, failures) if contract
      end

      {
        "id" => id,
        "passed" => failures.empty?,
        "observationPaths" => paths.compact.uniq.sort,
        "facts" => {
          "requestSHA256" => ViftyUIReview.sha256_json(expected_request),
          "source" => capture["source"]
        },
        "failures" => failures.uniq.sort
      }
    rescue StandardError => error
      failed_assertion(id, ["predicate evaluation failed closed: #{error.class}: #{error.message}"])
    end

    def failed_assertion(id, failures)
      {
        "id" => id,
        "passed" => false,
        "observationPaths" => [],
        "facts" => {},
        "failures" => failures.uniq.sort
      }
    end

    def validate_capture_contract(id, expected_request, capture, failures)
      require_condition(capture["schemaVersion"] == 1, "raw capture schema mismatch", failures)
      require_condition(capture["schemaID"] == RAW_SCHEMA_ID, "raw capture schema ID mismatch", failures)
      request = capture["request"]
      request = {} unless request.is_a?(Hash)
      require_condition(request["checkID"] == id, "check ID mismatch", failures)
      require_condition(request["semanticRequest"] == expected_request, "canonical semantic request mismatch", failures)
      expected_request_sha = ViftyUIReview.sha256_json(expected_request)
      require_condition(request["requestSHA256"] == expected_request_sha, "canonical request hash mismatch", failures)
      capture_id = request["captureID"]
      require_condition(capture_id.is_a?(String) && !capture_id.empty?, "capture ID is missing", failures)
      pid = request["processIdentifier"]
      require_condition(int32?(pid) && pid.positive?, "process identifier is invalid", failures)
      require_condition(
        request["windowIdentifier"] == "vifty-ui-review-ax-window-#{capture_id}",
        "window identifier does not bind the capture ID",
        failures
      )
      require_condition(
        request["rootIdentifier"] == "vifty.ax.fixture.root.#{capture_id}",
        "root identifier does not bind the capture ID",
        failures
      )
      require_condition(capture["source"] == "macos-accessibility-api", "capture source is invalid", failures)
      require_condition(capture["permissionTrusted"] == true, "Accessibility permission is not trusted", failures)
      require_condition(capture["promptRequested"] == false, "Accessibility permission prompt was requested", failures)

      target = {
        "processIdentifier" => pid,
        "windowIdentifier" => request["windowIdentifier"],
        "rootIdentifier" => request["rootIdentifier"]
      }
      require_condition(capture["initialTarget"] == target, "initial target identity mismatch", failures)
      require_condition(capture["finalTarget"] == target, "final target identity mismatch", failures)
      require_condition(capture["initialTarget"] == capture["finalTarget"], "target changed during traversal", failures)

      traversal = capture["traversal"]
      traversal = {} unless traversal.is_a?(Hash)
      raw_observations = capture["observations"]
      require_condition(
        raw_observations.is_a?(Array) && raw_observations.all? { |item| item.is_a?(Hash) },
        "observations must be a structured array",
        failures
      )
      observations = observations(capture)
      require_condition(traversal["complete"] == true, "Accessibility traversal is incomplete", failures)
      require_condition(traversal["truncationReasons"] == [], "Accessibility traversal was truncated", failures)
      require_condition(traversal["nodeCount"] == observations.length, "traversal node count mismatch", failures)
      require_condition(positive_swift_int?(traversal["maximumNodeCount"]), "maximum node count is invalid", failures)
      require_condition(positive_swift_int?(traversal["maximumDepth"]), "maximum depth is invalid", failures)
      require_condition(
        swift_int?(traversal["maximumNodeCount"]) && traversal["maximumNodeCount"] <= 16_384,
        "maximum node count exceeds the collector contract",
        failures
      )
      require_condition(
        swift_int?(traversal["maximumDepth"]) && traversal["maximumDepth"] <= 128,
        "maximum depth exceeds the collector contract",
        failures
      )
      if swift_int?(traversal["nodeCount"]) && swift_int?(traversal["maximumNodeCount"])
        require_condition(
          traversal["nodeCount"] <= traversal["maximumNodeCount"],
          "traversal exceeds its maximum node count",
          failures
        )
      end
      require_condition(capture["actionsPerformed"] == [], "Accessibility actions were performed", failures)
      require_condition(capture["readErrors"] == [], "capture contains read errors", failures)

      roots = nodes(request["rootIdentifier"], capture)
      require_condition(roots.length == 1, "capture root marker must occur exactly once", failures)
      root = only(roots)
      if root
        allows_scroll_area_root = SCROLL_CONTRACTS[id]&.fetch(2, false) == true
        require_condition(
          root["role"] == "AXGroup" || (allows_scroll_area_root && root["role"] == "AXScrollArea"),
          "capture root marker role mismatch",
          failures
        )
        require_condition(root["order"] == 0, "capture root marker must be first", failures)
        require_condition(
          observations.all? { |item| item["path"] == root["path"] || descendant?(item, root) },
          "observation is outside the capture root marker",
          failures
        )
      end

      paths = observations.map { |item| item["path"] }
      orders = observations.map { |item| item["order"] }
      require_condition(paths.uniq.length == paths.length, "observation paths are not unique", failures)
      require_condition(orders.uniq.length == orders.length, "observation orders are not unique", failures)
      require_condition(orders.all? { |order| swift_int?(order) } && orders == orders.sort, "observations are not in traversal order", failures)
      require_condition(orders == (0...orders.length).to_a, "observation orders are not contiguous", failures)
      require_condition(
        observations.all? { |item| item["readErrors"] == [] },
        "observation contains read errors",
        failures
      )
      require_condition(observations.all? { |item| finite_observation?(item) }, "observation geometry or value is non-finite", failures)
      validate_traversal_topology(capture, root, failures) if root
    end

    def validate_owner(capture, paths, failures)
      scope = unique(ID[:control_session], capture, failures)
      title = unique(ID[:control_session_title], capture, failures)
      summary = unique(ID[:control_session_summary], capture, failures)
      require_node(scope, "AXGroup", nil, nil, failures)
      require_node(title, "AXStaticText", "Vifty manual control active", nil, failures)
      require_node(summary, "AXStaticText", "Owner: Vifty manual control", nil, failures)
      require_descendant(title, scope, failures)
      require_descendant(summary, scope, failures)
      if title && summary
        require_condition(title["order"] < summary["order"], "owner title must precede owner summary", failures)
      end
      paths.concat([scope, title, summary].compact.map { |item| item["path"] })
    end

    def validate_fan_targets(capture, paths, failures)
      scope = unique(ID[:fan_status], capture, failures)
      left = unique(ID[:left_fan_draft_target], capture, failures)
      right = unique(ID[:right_fan_draft_target], capture, failures)
      require_node(scope, "AXGroup", nil, nil, failures)
      require_node(left, "AXStaticText", "Left Fan draft target", "Draft 2493 RPM", failures)
      require_node(right, "AXStaticText", "Right Fan draft target", "Draft 3080 RPM", failures)
      require_descendant(left, scope, failures)
      require_descendant(right, scope, failures)
      if left && right
        require_condition(left["value"] != right["value"], "left and right draft targets must be distinct", failures)
        require_condition(left["order"] < right["order"], "left draft target must precede right draft target", failures)
      end
      paths.concat([scope, left, right].compact.map { |item| item["path"] })
    end

    def validate_curve_controls(capture, paths, failures)
      scope = unique(ID[:curve_chart], capture, failures)
      require_node(scope, "AXGroup", nil, nil, failures)
      paths << scope["path"] if scope
      controls = CURVE_CONTROLS.map do |identifier, label, value|
        node = unique(identifier, capture, failures)
        require_node(node, "AXSlider", label, value, failures)
        require_condition(node && node["enabled"] == true, "#{identifier} must be enabled", failures)
        require_condition(node && Array(node["actions"]).to_set == Set["AXIncrement", "AXDecrement"], "#{identifier} action set mismatch", failures)
        require_descendant(node, scope, failures)
        paths << node["path"] if node
        node
      end.compact
      orders = controls.map { |item| item["order"] }
      require_condition(orders.all? { |order| swift_int?(order) } && orders == orders.sort, "curve controls are not in canonical order", failures)
    end

    def validate_separate_fan_curves_toggle(capture, paths, failures)
      toggle = unique(ID[:curve_separate_fans], capture, failures)
      chart = unique(ID[:curve_chart], capture, failures)
      root = only(nodes(capture.dig("request", "rootIdentifier"), capture))

      require_node(toggle, "AXCheckBox", "Separate fan curves", nil, failures)
      require_condition(toggle && toggle["enabled"] == true, "separate fan curves toggle must be enabled", failures)
      require_condition(toggle && toggle["selected"] == true, "separate fan curves toggle must be on", failures)
      require_condition(toggle && Array(toggle["actions"]).to_set == Set["AXPress"], "separate fan curves toggle action set mismatch", failures)
      require_condition(toggle && toggle["childCount"] == 0, "separate fan curves toggle must not expose children", failures)

      if toggle && chart
        require_condition(toggle["order"] < chart["order"], "separate fan curves toggle must precede the curve chart", failures)
        require_condition(!descendant?(toggle, chart), "separate fan curves toggle must remain outside the curve chart", failures)
      end

      toggle_frame = observation_frame(toggle)
      chart_frame = observation_frame(chart)
      root_frame = observation_frame(root)
      if toggle_frame && chart_frame && root_frame
        require_condition(
          toggle_frame["width"].positive? && toggle_frame["height"].positive?,
          "separate fan curves toggle frame must be positive",
          failures
        )
        require_condition(
          frame_contains?(root_frame, toggle_frame, 0.5),
          "separate fan curves toggle must be fully visible inside the capture root",
          failures
        )
        require_condition(
          toggle_frame["y"] + toggle_frame["height"] <= chart_frame["y"] + 0.5,
          "separate fan curves toggle must be visually above the curve chart",
          failures
        )
      else
        require_condition(false, "separate fan curves toggle, chart, and capture root must expose frames", failures)
      end

      paths.concat([toggle, chart].compact.map { |item| item["path"] })
    end

    def validate_effective_curve_summaries(capture, paths, failures)
      scope = unique(ID[:curve_effective_summaries], capture, failures)
      chart = unique(ID[:curve_chart], capture, failures)
      require_node(scope, "AXGroup", nil, nil, failures)

      summaries = EFFECTIVE_CURVE_SUMMARIES.each_with_index.map do |(identifier, label, value), index|
        node = unique(identifier, capture, failures)
        require_node(node, "AXStaticText", label, value, failures)
        require_condition(node && node["childCount"] == 0, "#{identifier} must be a leaf summary", failures)
        require_descendant(node, scope, failures)
        if scope && node
          require_condition(
            node["path"] == "#{scope["path"]}/#{index}",
            "#{identifier} must be direct summary child #{index}",
            failures
          )
        end
        node
      end.compact

      if scope
        summary_descendants = descendants(scope, capture)
        require_condition(
          scope["childCount"] == EFFECTIVE_CURVE_SUMMARIES.length &&
            summary_descendants.length == EFFECTIVE_CURVE_SUMMARIES.length &&
            summary_descendants.all? { |item| item["role"] == "AXStaticText" },
          "effective curve summaries must expose exactly two direct static-text children",
          failures
        )
      end

      if chart && scope
        chart_last_order = ([chart["order"]] + descendants(chart, capture).map { |item| item["order"] }).max
        require_condition(chart_last_order < scope["order"], "effective curve summaries must follow the curve chart", failures)
        require_condition(!descendant?(scope, chart), "effective curve summaries must remain outside the curve chart", failures)
        summaries.each do |summary|
          require_condition(
            !descendant?(summary, chart),
            "#{summary["identifier"] || summary["path"]} must remain outside the curve chart",
            failures
          )
        end
      end

      orders = summaries.map { |item| item["order"] }
      require_condition(
        orders.all? { |order| swift_int?(order) } && orders == orders.sort,
        "effective curve summaries are not in fan order",
        failures
      )
      paths.concat([scope, chart, *summaries].compact.map { |item| item["path"] })
    end

    def validate_sensors(capture, paths, failures)
      scope = unique(ID[:sensor_list], capture, failures)
      contracts = [
        [ID[:sensor_cpu], "CPU Efficiency", "64.0 degrees Celsius, SMC", true],
        [ID[:sensor_gpu], "GPU Hotspot", "83.0 degrees Celsius, HID", false],
        [ID[:sensor_palm], "Palm Rest", "37.0 degrees Celsius, HID", false]
      ]
      require_node(scope, "AXOpaqueProviderGroup", nil, nil, failures)
      paths << scope["path"] if scope

      if scope
        require_condition(
          scope["actions"] == ["AXScrollToBottom", "AXScrollToTop"],
          "sensor list action set mismatch",
          failures
        )
        require_condition(scope["childCount"] == contracts.length, "sensor list must expose exactly three direct children", failures)
        prefix = scope["path"].to_s + "/"
        direct_children = observations(capture).select do |item|
          path = item["path"]
          path.is_a?(String) && path.start_with?(prefix) && !path.delete_prefix(prefix).include?("/")
        end
        require_condition(direct_children.length == contracts.length, "sensor list direct-child count mismatch", failures)
        require_condition(
          direct_children.map { |item| item["identifier"] } == contracts.map(&:first),
          "sensor list direct-child order mismatch",
          failures
        )
      end

      selected_count = 0
      contracts.each_with_index do |(identifier, label, value, selected), index|
        node = unique(identifier, capture, failures)
        require_node(node, "AXButton", label, value, failures)
        require_condition(node && node["enabled"] == true, "#{identifier} must be enabled", failures)
        if selected
          require_condition(node && node["selected"] == true, "#{identifier} must expose the selected trait", failures)
        else
          require_condition(node && node["selected"] != true, "#{identifier} must not expose the selected trait", failures)
        end
        require_condition(node && node["actions"] == ["AXPress", "AXScrollToVisible"], "#{identifier} action set mismatch", failures)
        require_condition(node && node["childCount"] == 0, "#{identifier} must be a leaf sensor button", failures)
        require_condition(
          node && scope && node["path"] == "#{scope["path"]}/#{index}",
          "#{identifier} must be direct sensor child #{index}",
          failures
        )
        selected_count += 1 if node && node["selected"] == true
        paths << node["path"] if node
      end
      require_condition(selected_count == 1, "exactly one sensor must be selected", failures)
    end

    def validate_temperature_roles(capture, paths, failures)
      scope = unique(ID[:temperature_metrics], capture, failures)
      curve = unique(ID[:curve_sensor_metric], capture, failures)
      highest = unique(ID[:highest_temperature_metric], capture, failures)
      require_node(scope, "AXGroup", nil, nil, failures)
      require_node(curve, "AXStaticText", "Curve sensor", "Curve sensor · CPU Efficiency", failures)
      require_node(highest, "AXStaticText", "Highest temperature", "Highest 83.0 °C", failures)
      require_descendant(curve, scope, failures)
      require_descendant(highest, scope, failures)
      if curve && highest
        require_condition(curve["order"] < highest["order"], "curve sensor metric must precede highest metric", failures)
        require_condition(curve["path"] != highest["path"], "temperature roles must use separate nodes", failures)
      end
      if scope
        count = descendants(scope, capture).count { |item| item["role"] == "AXStaticText" }
        require_condition(count == 2, "temperature metrics must expose exactly two text roles", failures)
      end
      paths.concat([scope, curve, highest].compact.map { |item| item["path"] })
    end

    def validate_notifications(capture, paths, failures)
      scope = unique(ID[:notifications], capture, failures)
      open_settings = unique(ID[:notification_open_settings], capture, failures)
      require_node(scope, "AXGroup", nil, nil, failures)
      require_node(open_settings, "AXButton", "Open Notification Settings", nil, failures)
      require_condition(open_settings && open_settings["enabled"] == true, "Open Notification Settings must be enabled", failures)
      require_condition(open_settings && open_settings["actions"] == ["AXPress"], "Open Notification Settings action set mismatch", failures)
      require_descendant(open_settings, scope, failures)
      require_condition(nodes(ID[:notification_send_test], capture).empty?, "Send Test Notification must be absent when permission is denied", failures)
      if scope
        send_test = descendants(scope, capture).any? do |item|
          item["role"] == "AXButton" && item["label"] == "Send Test Notification"
        end
        require_condition(!send_test, "Send Test Notification action must be absent when permission is denied", failures)
      end
      paths.concat([scope, open_settings].compact.map { |item| item["path"] })

      contracts = [
        [ID[:notification_helper_failure], "Helper failure"],
        [ID[:notification_thermal_pressure], "High thermal pressure"],
        [ID[:notification_auto_restore], "Auto restore failure"],
        [ID[:notification_battery_drain], "Plugged-in battery drain"],
        [ID[:notification_agent_cooling], "Agent cooling attention"]
      ]
      contracts.each do |identifier, label|
        node = unique(identifier, capture, failures)
        require_node(node, "AXCheckBox", label, nil, failures)
        require_condition(node && node["enabled"] == true, "#{identifier} must be enabled", failures)
        require_condition(node && node["selected"] == true, "#{identifier} must be selected", failures)
        require_condition(node && node["actions"] == ["AXPress"], "#{identifier} action set mismatch", failures)
        require_descendant(node, scope, failures)
        paths << node["path"] if node
      end
      if scope
        count = descendants(scope, capture).count { |item| item["role"] == "AXCheckBox" }
        require_condition(count == contracts.length, "notification settings must expose exactly five event checkboxes", failures)
      end
    end

    def validate_settings_traversal(capture, paths, failures)
      root = unique(capture.dig("request", "rootIdentifier"), capture, failures)
      tab_group = unique(ID[:settings_tabs], capture, failures)
      pane = unique(ID[:settings_pane_general], capture, failures)
      require_node(root, "AXGroup", nil, nil, failures)
      require_node(tab_group, "AXGroup", "Settings sections", nil, failures)
      require_node(pane, "AXGroup", "General settings", nil, failures)
      if root
        require_condition(root["childCount"] == 2, "Settings capture root must expose exactly the tab group and selected pane", failures)
        require_condition(tab_group && tab_group["path"] == "#{root["path"]}/0", "Settings tab group must be the first direct child of the capture root", failures)
        require_condition(pane && pane["path"] == "#{root["path"]}/1", "selected Settings pane must be the second direct child of the capture root", failures)
      end
      paths.concat([root, tab_group, pane].compact.map { |item| item["path"] })
      contracts = [
        [ID[:settings_tab_general], "General", "Selected", true],
        [ID[:settings_tab_menu_bar], "Menu Bar", "Not selected", false],
        [ID[:settings_tab_notifications], "Notifications", "Not selected", false],
        [ID[:settings_tab_agent_workflows], "Agent Workflows", "Not selected", false]
      ]
      tabs = contracts.each_with_index.map do |(identifier, label, value, selected), index|
        node = unique(identifier, capture, failures)
        require_node(node, "AXButton", label, nil, failures)
        typed_value = node && node["value"]
        require_condition(
          typed_value.is_a?(Hash) && typed_value["type"] == "string" && typed_value["value"] == value,
          "#{identifier} typed string value mismatch",
          failures
        )
        require_condition(node && node["enabled"] == true, "#{identifier} must be enabled", failures)
        if selected
          require_condition(node && node["selected"] == true, "#{identifier} must expose the selected trait", failures)
        else
          require_condition(node && node["selected"] != true, "#{identifier} must not expose the selected trait", failures)
        end
        require_condition(node && node["actions"] == ["AXPress"], "#{identifier} action set mismatch", failures)
        if tab_group
          require_condition(
            node && node["path"] == "#{tab_group["path"]}/#{index}",
            "#{identifier} must be direct child #{index} of the Settings tab group",
            failures
          )
        end
        paths << node["path"] if node
        node
      end.compact
      orders = tabs.map { |item| item["order"] }
      require_condition(orders.all? { |order| swift_int?(order) } && orders == orders.sort, "Settings tabs are not in logical order", failures)
      if tab_group
        tab_descendants = descendants(tab_group, capture)
        require_condition(
          tab_group["childCount"] == contracts.length &&
            tab_descendants.length == contracts.length &&
            tab_descendants.all? { |item| item["role"] == "AXButton" },
          "Settings must expose exactly four direct tab buttons",
          failures
        )
      end
      if pane && tabs.last
        require_condition(tabs.last["order"] < pane["order"], "selected Settings pane must follow tab controls", failures)
      end
    end

    def validate_no_duplicate_chart_elements(capture, failures)
      scope = only(nodes(ID[:curve_chart], capture))
      return unless scope
      chart_descendants = descendants(scope, capture)
      require_condition(
        chart_descendants.length == CURVE_CONTROLS.length,
        "chart must expose exactly the six canonical slider descendants",
        failures
      )
      require_condition(
        chart_descendants.all? { |item| item["role"] == "AXSlider" },
        "chart exposes a non-slider descendant",
        failures
      )
      actual_ids = chart_descendants.map { |item| item["identifier"] }.compact.uniq.sort
      expected_ids = CURVE_CONTROLS.map(&:first).uniq.sort
      require_condition(actual_ids == expected_ids, "chart descendant identifiers do not match the canonical controls", failures)
    end

    def validate_scroll(capture, contract, paths, failures)
      scroll_identifier, anchor_identifier, allows_capture_root_fallback = contract
      canonical_areas = nodes(scroll_identifier, capture)
      area = if canonical_areas.length == 1
               only(canonical_areas)
             elsif canonical_areas.empty? && allows_capture_root_fallback
               roots = nodes(capture.dig("request", "rootIdentifier"), capture)
               require_condition(
                 roots.length == 1 && only(roots)["role"] == "AXScrollArea",
                 "settings scroll fallback must be the unique exact capture-root AXScrollArea",
                 failures
               )
               roots.length == 1 && only(roots)["role"] == "AXScrollArea" ? only(roots) : nil
             else
               require_condition(false, "#{scroll_identifier} must occur exactly once", failures)
               nil
             end
      anchor = unique(anchor_identifier, capture, failures)
      require_node(area, "AXScrollArea", nil, nil, failures)
      require_node(anchor, "AXStaticText", "End of content", nil, failures)
      require_descendant(anchor, area, failures)
      paths.concat([area, anchor].compact.map { |item| item["path"] })
      return unless area

      require_condition(
        Array(area["actions"]).include?("AXScrollUpByPage") && Array(area["actions"]).include?("AXScrollDownByPage"),
        "scroll area must expose page-up and page-down actions",
        failures
      )
      evidence = Array(capture["scrollEvidence"]).select do |item|
        item.is_a?(Hash) && item["scrollAreaPath"] == area["path"]
      end
      require_condition(evidence.length == 1, "scroll area must have exactly one evidence record", failures)
      scroll = only(evidence)
      return unless scroll
      bar_path = scroll["verticalScrollBarPath"]
      require_condition(
        bar_path.is_a?(String) && bar_path.start_with?(area["path"].to_s + "/"),
        "vertical scrollbar is not structurally linked to its scroll area",
        failures
      )
      bars = observations(capture).select { |item| item["path"] == bar_path }
      require_condition(bars.length == 1, "scroll evidence must reference one vertical scrollbar", failures)
      bar = only(bars)
      require_condition(bar && bar["role"] == "AXScrollBar", "vertical scrollbar role mismatch", failures)
      minimum = scroll["minimumValue"]
      maximum = scroll["maximumValue"]
      current = scroll["currentValue"]
      require_condition(scroll.key?("minimumValue"), "scroll minimum availability is missing", failures)
      require_condition(scroll.key?("maximumValue"), "scroll maximum availability is missing", failures)
      require_condition(finite_number?(current), "scroll current is non-finite", failures)
      bounds_both_unavailable = minimum.nil? && maximum.nil?
      bounds_both_present = !minimum.nil? && !maximum.nil?
      require_condition(
        bounds_both_unavailable || bounds_both_present,
        "scrollbar bounds must be both present or both unavailable",
        failures
      )
      if bounds_both_present
        require_condition(finite_number?(minimum), "scroll minimum is non-finite", failures)
        require_condition(finite_number?(maximum), "scroll maximum is non-finite", failures)
      end
      if finite_number?(minimum) && finite_number?(maximum)
        require_condition(maximum > minimum, "scrollbar range is empty", failures)
      end
      if finite_number?(minimum) && finite_number?(maximum) && finite_number?(current)
        require_condition(current >= minimum && current <= maximum, "scrollbar value is outside its range", failures)
        require_condition(numerically_equal?(current, minimum), "scrollbar must be captured at its initial value", failures)
      end
      viewport = scroll["viewportHeight"]
      content = scroll["contentHeight"]
      require_condition(finite_number?(viewport) && viewport.positive?, "scroll viewport height is invalid", failures)
      require_condition(finite_number?(content) && finite_number?(viewport) && content > viewport, "scroll content does not overflow", failures)
      if bar && finite_number?(current)
        numeric = typed_numeric_value(bar["value"])
        require_condition(numeric && numerically_equal?(numeric, current), "scrollbar typed value does not match structural evidence", failures)
      end
      validate_scroll_geometry(area, anchor, scroll, failures)
      paths << bar["path"] if bar
    end

    def validate_scroll_geometry(area, anchor, scroll, failures)
      area_position = area["position"]
      area_size = area["size"]
      unless point?(area_position) && size?(area_size) && area_size["width"].positive? && area_size["height"].positive?
        failures << "scroll area geometry is missing or empty"
        return
      end
      if finite_number?(scroll["viewportHeight"])
        require_condition(
          approximately_equal?(area_size["height"], scroll["viewportHeight"]),
          "scroll viewport height does not match the scroll area frame",
          failures
        )
      end
      anchor_position = anchor && anchor["position"]
      anchor_size = anchor && anchor["size"]
      unless point?(anchor_position) && size?(anchor_size) && anchor_size["width"].positive? && anchor_size["height"].positive?
        failures << "scroll end-anchor geometry is missing or empty"
        return
      end
      area_min_y = area_position["y"]
      area_max_y = area_min_y + area_size["height"]
      anchor_min_y = anchor_position["y"]
      anchor_max_y = anchor_min_y + anchor_size["height"]
      require_condition(
        anchor_max_y <= area_min_y || anchor_min_y >= area_max_y,
        "scroll end anchor is already inside the initial viewport",
        failures
      )
      structural_span = [area_max_y, anchor_max_y].max - [area_min_y, anchor_min_y].min
      if finite_number?(scroll["contentHeight"])
        require_condition(
          scroll["contentHeight"] + 0.5 >= structural_span,
          "declared scroll content height cannot contain the observed end anchor",
          failures
        )
      end
    end

    def validate_traversal_topology(capture, root, failures)
      by_path = observations(capture).each_with_object({}) do |item, result|
        result[item["path"]] = item unless result.key?(item["path"])
      end
      observations(capture).each do |item|
        components = relative_path_components(item["path"], root["path"])
        unless components
          failures << "observation path is not canonical: #{item["path"]}"
          next
        end
        require_condition(item["depth"] == components.length, "observation depth does not match its path: #{item["path"]}", failures)
        maximum_depth = capture.dig("traversal", "maximumDepth")
        if swift_int?(item["depth"]) && swift_int?(maximum_depth)
          require_condition(item["depth"] <= maximum_depth, "observation exceeds maximum traversal depth: #{item["path"]}", failures)
        end
        child_count = item["childCount"]
        require_condition(swift_int?(child_count), "observation child count is missing: #{item["path"]}", failures)
        require_condition(swift_int?(child_count) && child_count >= 0, "observation child count is invalid: #{item["path"]}", failures)
        if item["path"] != root["path"]
          parent_path = item["path"].to_s.split("/")[0...-1].join("/")
          parent = by_path[parent_path]
          require_condition(!parent.nil?, "observation parent is missing: #{item["path"]}", failures)
          if parent && swift_int?(parent["order"]) && swift_int?(item["order"])
            require_condition(parent["order"] < item["order"], "observation precedes its parent: #{item["path"]}", failures)
          end
        end
        prefix = item["path"].to_s + "/"
        numeric_children = observations(capture).map do |candidate|
          path = candidate["path"]
          next unless path.is_a?(String) && path.start_with?(prefix)
          suffix = path.delete_prefix(prefix)
          next if suffix.include?("/") || !/\A(?:0|[1-9][0-9]*)\z/.match?(suffix)
          value = suffix.to_i
          next unless swift_int?(value)
          value
        end.compact.sort
        if swift_int?(child_count)
          require_condition(numeric_children.length == child_count, "observation child count mismatch: #{item["path"]}", failures)
          require_condition(numeric_children == (0...child_count).to_a, "observation child indexes are not contiguous: #{item["path"]}", failures) if child_count >= 0
        end
      end

      expected_preorder_paths = []
      visited_paths = {}
      append_subtree = lambda do |path|
        item = by_path[path]
        next unless item && !visited_paths[path]
        visited_paths[path] = true
        expected_preorder_paths << path
        child_count = item["childCount"]
        next unless swift_int?(child_count) && child_count >= 0 && child_count <= observations(capture).length
        (0...child_count).each { |index| append_subtree.call("#{path}/#{index}") }
        vertical = "#{path}/@vertical"
        append_subtree.call(vertical) if by_path.key?(vertical)
      end
      append_subtree.call(root["path"])
      require_condition(
        expected_preorder_paths == observations(capture).map { |item| item["path"] },
        "observations are not in strict depth-first pre-order",
        failures
      )
    end

    def relative_path_components(path, root_path)
      return [] if path == root_path
      return nil unless path.is_a?(String) && root_path.is_a?(String)
      prefix = root_path + "/"
      return nil unless path.start_with?(prefix)
      components = path.delete_prefix(prefix).split("/", -1)
      return nil if components.empty?
      components.each_with_index do |component, index|
        if component == "@vertical"
          return nil unless index == components.length - 1
        elsif !/\A(?:0|[1-9][0-9]*)\z/.match?(component) || !swift_int?(component.to_i)
          return nil
        end
      end
      components
    end

    def observations(capture)
      Array(capture["observations"]).select { |item| item.is_a?(Hash) }
    end

    def nodes(identifier, capture)
      observations(capture).select { |item| item["identifier"] == identifier }
    end

    def descendants(parent, capture)
      observations(capture).select { |item| descendant?(item, parent) }
    end

    def unique(identifier, capture, failures)
      matches = nodes(identifier, capture)
      require_condition(matches.length == 1, "#{identifier} must occur exactly once", failures)
      only(matches)
    end

    def require_node(node, role, label, value, failures)
      return unless node
      name = node["identifier"] || node["path"]
      require_condition(node["role"] == role, "#{name} role mismatch", failures)
      unless label.nil?
        require_condition(node["label"] == label, "#{name} label mismatch", failures)
      end
      require_condition(observed_value(node) == value, "#{name} value mismatch", failures) unless value.nil?
    end

    def require_descendant(child, parent, failures)
      return unless child && parent
      require_condition(descendant?(child, parent), "#{child["identifier"] || child["path"]} is outside its required scope", failures)
    end

    def descendant?(child, parent)
      child["path"].is_a?(String) && parent["path"].is_a?(String) && child["path"].start_with?(parent["path"] + "/")
    end

    def observation_frame(node)
      return nil unless node.is_a?(Hash) && point?(node["position"]) && size?(node["size"])
      {
        "x" => node.dig("position", "x"),
        "y" => node.dig("position", "y"),
        "width" => node.dig("size", "width"),
        "height" => node.dig("size", "height")
      }
    end

    def frame_contains?(outer, inner, tolerance)
      inner["x"] >= outer["x"] - tolerance &&
        inner["y"] >= outer["y"] - tolerance &&
        inner["x"] + inner["width"] <= outer["x"] + outer["width"] + tolerance &&
        inner["y"] + inner["height"] <= outer["y"] + outer["height"] + tolerance
    end

    def observed_value(node)
      return node["valueDescription"] if node["valueDescription"].is_a?(String)
      value = node["value"]
      value["value"] if value.is_a?(Hash) && value["type"] == "string"
    end

    def finite_observation?(item)
      return false unless item.is_a?(Hash)
      return false unless finite_typed_value?(item["value"])
      return false if item.key?("position") && !point?(item["position"])
      return false if item.key?("size") && !size?(item["size"])
      true
    end

    def finite_typed_value?(value)
      return true if value.nil?
      return false unless value.is_a?(Hash)
      case value["type"]
      when "string"
        value["value"].is_a?(String)
      when "boolean"
        value["value"] == true || value["value"] == false
      when "signed-integer"
        value["value"].is_a?(Integer) && INT64_RANGE.cover?(value["value"])
      when "unsigned-integer"
        value["value"].is_a?(Integer) && UINT64_RANGE.cover?(value["value"])
      when "number"
        finite_number?(value["value"])
      when "point"
        point?(value["value"])
      when "size"
        size?(value["value"])
      when "rectangle"
        rectangle?(value["value"])
      when "range"
        range = value["value"]
        range.is_a?(Hash) && swift_int?(range["location"]) && range["location"] >= 0 &&
          swift_int?(range["length"]) && range["length"] >= 0
      when "error"
        int32?(value["value"])
      else
        false
      end
    end

    def typed_numeric_value(value)
      return nil unless value.is_a?(Hash)
      return nil unless %w[number signed-integer unsigned-integer].include?(value["type"])
      numeric = value["value"]
      numeric.to_f if finite_number?(numeric)
    end

    def point?(value)
      value.is_a?(Hash) && finite_number?(value["x"]) && finite_number?(value["y"])
    end

    def size?(value)
      value.is_a?(Hash) && finite_number?(value["width"]) && finite_number?(value["height"]) &&
        value["width"] >= 0 && value["height"] >= 0
    end

    def rectangle?(value)
      value.is_a?(Hash) && finite_number?(value["x"]) && finite_number?(value["y"]) &&
        finite_number?(value["width"]) && finite_number?(value["height"]) &&
        value["width"] >= 0 && value["height"] >= 0
    end

    def finite_number?(value)
      value.is_a?(Numeric) && value.to_f.finite?
    end

    def swift_int?(value)
      value.is_a?(Integer) && INT64_RANGE.cover?(value)
    end

    def positive_swift_int?(value)
      swift_int?(value) && value.positive?
    end

    def int32?(value)
      value.is_a?(Integer) && INT32_RANGE.cover?(value)
    end

    def approximately_equal?(left, right)
      (left.to_f - right.to_f).abs <= 0.5
    end

    def numerically_equal?(left, right)
      scale = [1.0, left.to_f.abs, right.to_f.abs].max
      (left.to_f - right.to_f).abs <= Float::EPSILON * 8 * scale
    end

    def require_condition(condition, message, failures)
      failures << message unless condition
    end

    def only(items)
      items.length == 1 ? items.first : nil
    end
  end
end
