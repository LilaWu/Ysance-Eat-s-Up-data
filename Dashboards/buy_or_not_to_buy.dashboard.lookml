- dashboard: bqmlooker
  title: BQML²OOKER
  layout: newspaper
  preferred_viewer: dashboards-next
  description: ''
  elements:
  - title: Country List
    name: Country List
    model: eats_up_data_ysance_3
    explore: full_data
    type: looker_grid
    fields: [full_data.country]
    sorts: [full_data.country]
    limit: 500
    show_view_names: false
    show_row_numbers: true
    transpose: false
    truncate_text: true
    hide_totals: false
    hide_row_totals: false
    size_to_fit: true
    table_theme: white
    limit_displayed_rows: false
    enable_conditional_formatting: false
    header_text_alignment: left
    header_font_size: 12
    rows_font_size: 12
    conditional_formatting_include_totals: false
    conditional_formatting_include_nulls: false
    x_axis_gridlines: false
    y_axis_gridlines: true
    show_y_axis_labels: true
    show_y_axis_ticks: true
    y_axis_tick_density: default
    y_axis_tick_density_custom: 5
    show_x_axis_label: true
    show_x_axis_ticks: true
    y_axis_scale_mode: linear
    x_axis_reversed: false
    y_axis_reversed: false
    plot_size_by_field: false
    trellis: ''
    stacking: ''
    legend_position: center
    point_style: none
    show_value_labels: false
    label_density: 25
    x_axis_scale: auto
    y_axis_combined: true
    ordering: none
    show_null_labels: false
    show_totals_labels: false
    show_silhouette: false
    totals_color: "#808080"
    defaults_version: 1
    series_types: {}
    listen: {}
    row: 0
    col: 0
    width: 8
    height: 6
  - title: Country HotMap
    name: Country HotMap
    model: eats_up_data_ysance_3
    explore: full_data
    type: looker_map
    fields: [full_data.country, full_data.predicted_will_purchase, nombre_de_country,
      full_data.id]
    filters:
      full_data.country: ''
    sorts: [full_data.country]
    limit: 500
    dynamic_fields: [{measure: nombre_de_country, based_on: full_data.country, expression: '',
        label: Nombre de Country, type: count_distinct, _kind_hint: measure, _type_hint: number},
      {category: dimension, description: '', label: Did purchase or not Groupes, value_format: !!null '',
        value_format_name: !!null '', calculation_type: group_by, dimension: did_purchase_or_not_groupes,
        args: [full_data.predicted_will_purchase, [!ruby/hash:ActiveSupport::HashWithIndifferentAccess {
              label: '', filter: ''}], !!null ''], _kind_hint: dimension, _type_hint: string}]
    map_plot_mode: points
    heatmap_gridlines: false
    heatmap_gridlines_empty: false
    heatmap_opacity: 0.5
    show_region_field: true
    draw_map_labels_above_data: true
    map_tile_provider: light
    map_position: fit_data
    map_scale_indicator: 'off'
    map_pannable: true
    map_zoomable: true
    map_marker_type: circle
    map_marker_icon_name: default
    map_marker_radius_mode: proportional_value
    map_marker_units: meters
    map_marker_proportional_scale_type: linear
    map_marker_color_mode: fixed
    show_view_names: false
    show_legend: true
    quantize_map_value_colors: false
    reverse_map_value_colors: false
    series_types: {}
    defaults_version: 1
    row: 0
    col: 8
    width: 8
    height: 6
