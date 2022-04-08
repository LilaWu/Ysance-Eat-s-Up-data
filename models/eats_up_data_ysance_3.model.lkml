# Define the database connection to be used for this model.
connection: "eatsupdata_ysance3"

# Datagroups define a caching policy for an Explore. To learn more,
# use the Quick Help panel on the right to see documentation.

datagroup: eats_up_data_ysance_3_default_datagroup {
  # sql_trigger: SELECT MAX(id) FROM etl_log;;
  max_cache_age: "1 hour"
}

persist_with: eats_up_data_ysance_3_default_datagroup

explore: full_data {
  label: "Data and Prediction"
  join: model_prediction_log_reg {
    relationship: one_to_one
    type: inner
    sql_on: ${model_prediction_log_reg.id} = ${full_data.id} ;;
  }
  join: model_prediction_tree_xgboost {
    relationship: one_to_one
    type: inner
    sql_on: ${model_prediction_tree_xgboost.id} = ${full_data.id} ;;
  }
  join: model_prediction_dnn_classifier {
    relationship: one_to_one
    type: inner
    sql_on: ${model_prediction_dnn_classifier.id} = ${full_data.id} ;;
  }
  join: model_prediction_automl_classifier{
    relationship: one_to_one
    type: inner
    sql_on: ${model_prediction_automl_classifier.id} = ${full_data.id} ;;
  }
}

view: full_data {
  derived_table:{
    sql:
       SELECT
          IF(totals.transactions IS NULL, "0", "1") AS predicted_will_purchase,
          IFNULL(device.operatingSystem, "") AS os,
          device.isMobile AS is_mobile,
          IFNULL(geoNetwork.country, "") AS country,
          IFNULL(totals.pageviews, 0) AS pageviews,
          date AS date,
          fullvisitorid AS id
        FROM
          `bigquery-public-data.google_analytics_sample.ga_sessions_*`
        WHERE
          _TABLE_SUFFIX BETWEEN '20160801' AND '20170401'
        ;;
  }


  dimension: id {}

  dimension: predicted_will_purchase {
    type: string
    label: "Did purchase or not"
  }

  dimension: os {type:string}
  dimension: is_mobile {type:string}
  dimension: country {
    type:string
    map_layer_name: countries}
  dimension: pageviews {type:string}

  measure: id_count { # Base measure #1
    type: count_distinct
    sql: ${id} ;;
  }
}

explore: training_input {}
view: training_input {
  derived_table: {
    sql: SELECT * FROM ${full_data.SQL_TABLE_NAME} WHERE date BETWEEN '20160801' AND '20170130';;
  }
}

explore: testing_input {}
view: testing_input {
  derived_table: {
    sql: SELECT * FROM ${full_data.SQL_TABLE_NAME} WHERE date BETWEEN '20170201' AND '20170228' ;;
  }
}

explore: predict_input {}
view: predict_input {
  derived_table: {
    sql: SELECT * FROM ${full_data.SQL_TABLE_NAME} WHERE date BETWEEN '20170301' AND '20170401' ;;
  }
}

##################################################
# ML 1 : LOGISTIC REGRESSION
##################################################

explore: future_purchase_model_log_reg {}:
view: future_purchase_model_log_reg {
  derived_table: {
    persist_for: "24 hours" # need to have persistence
    sql_create:
      CREATE OR REPLACE MODEL ${SQL_TABLE_NAME}
      OPTIONS(model_type='logistic_reg'
        , labels=['predicted_will_purchase']
        , min_rel_progress = 0.005
        , max_iterations = 40
        , auto_class_weights=true) AS
      SELECT
         * EXCEPT(id)
      FROM ${training_input.SQL_TABLE_NAME};;
  }
}

explore: model_evaluation_log_reg {}
view: model_evaluation_log_reg {
  derived_table: {
    sql: SELECT
          roc_auc,
            CASE
              WHEN roc_auc > .9 THEN 'good'
              WHEN roc_auc > .8 THEN 'fair'
              WHEN roc_auc > .7 THEN 'decent'
              WHEN roc_auc > .6 THEN 'not great'
              ELSE 'poor' END AS model_quality,
          log_loss,
          accuracy,
            CASE
              WHEN accuracy > .9 THEN 'good'
              WHEN accuracy > .8 THEN 'fair'
              WHEN accuracy > .7 THEN 'decent'
              WHEN accuracy > .6 THEN 'not great'
              ELSE 'poor' END AS model_accuracy,
         FROM ML.EVALUATE(MODEL ${future_purchase_model_log_reg.SQL_TABLE_NAME},(SELECT * FROM ${testing_input.SQL_TABLE_NAME})) ;;
  }
  dimension: model_quality {}
  dimension: iteration {}
  dimension: fi_score {}
  dimension: recall {type: number value_format_name:percent_2}
  dimension: accuracy {type: number value_format_name:percent_2}
  dimension: f1_score {type: number value_format_name:percent_2}
  dimension: log_loss {type: number}
  dimension: roc_auc {type: number}
}

explore: model_prediction_log_reg {}
view: model_prediction_log_reg {
  derived_table: {
    sql: SELECT * FROM ML.PREDICT(
          MODEL ${future_purchase_model_log_reg.SQL_TABLE_NAME},
          (SELECT * FROM ${predict_input.SQL_TABLE_NAME}));;
  }

  dimension: predicted_will_purchase {type:string}
  dimension: id {
    type: string}
  dimension: country {
    type:string
    map_layer_name: countries
  }
  dimension: os {}
  dimension: is_mobile {}
  measure: id_count{
    type: count_distinct
    sql: ${id} ;;
  }
  dimension: pageviews {}
  measure: pageviews_sum {
    type: sum
    sql: ${pageviews} ;;}
  dimension: pk2_opportunity_id {hidden:yes}
  dimension: pk2_date {hidden:yes}
  dimension: result {type: number}
  dimension: predicted_result {type: number}
  dimension: renewal_prob {type: number sql:(SELECT prob FROM UNNEST(${TABLE}.predicted_result_probs) WHERE label=1);; value_format_name: percent_2}
  measure: count {type:count drill_fields: [account.name, renewal_prob, predicted_result, result]}
  measure: predicted_renewals {type:sum sql:${predicted_result};;}
  measure: predicted_nonrenewals {type:sum sql:1-${predicted_result};;}
  measure: ev_renewals {type:sum sql:${renewal_prob};; value_format_name:decimal_1}
  measure: actual_renewals {type:sum sql:${result};;}
  measure: actual_nonrenewals {type:sum sql:1-${result};;}
  measure: false_positives {
    type:count
    filters: {field: predicted_result value: "1"}
    filters: {field: result value:"0"}
    drill_fields: [account.name, renewal_prob, predicted_result, result]

}
}

explore: roc_curve_log_reg {}
view: roc_curve_log_reg {
  derived_table: {
    sql: SELECT * FROM ml.ROC_CURVE(
        MODEL ${future_purchase_model_log_reg.SQL_TABLE_NAME},
        (SELECT * FROM ${testing_input.SQL_TABLE_NAME}));;
  }
  dimension: threshold {
    type: number
    value_format_name: decimal_4
    link: {
      label: "Campaign List Creator"
      url: "/dashboards/202?Customer%20Propensity%20to%20Purchase=>{{ rendered_value | encode_uri }}"
      icon_url: "http://www.looker.com/favicon.ico"
    }
  }
  dimension: recall {type: number value_format_name: percent_2}
  dimension: false_positive_rate {type: number}
  dimension: true_positives {type: number }
  dimension: false_positives {type: number}
  dimension: true_negatives {type: number}
  dimension: false_negatives {type: number }
  dimension: precision {
    type:  number
    value_format_name: percent_2
    sql:  ${true_positives} / NULLIF((${true_positives} + ${false_positives}),0);;
    description: "Equal to true positives over all positives. Indicative of how false positives are penalized. Set high to get no false positives"
  }
  measure: total_false_positives {
    type: sum
    sql: ${false_positives} ;;
  }
  measure: total_true_positives {
    type: sum
    sql: ${true_positives} ;;
  }
  dimension: threshold_accuracy {
    type: number
    value_format_name: percent_2
    sql:  1.0*(${true_positives} + ${true_negatives}) / NULLIF((${true_positives} + ${true_negatives} + ${false_positives} + ${false_negatives}),0);;
  }
  dimension: threshold_f1 {
    type: number
    value_format_name: percent_3
    sql: 2.0*${recall}*${precision} / NULLIF((${recall}+${precision}),0);;
  }
}

explore: future_purchase_model_training_info_log_reg {}
view: future_purchase_model_training_info_log_reg {
  derived_table: {
    sql: SELECT  * FROM ml.TRAINING_INFO(MODEL ${future_purchase_model_log_reg.SQL_TABLE_NAME});;
  }
  dimension: training_run {type: number}
  dimension: iteration {type: number}
  dimension: loss_raw {sql: ${TABLE}.loss;; type: number hidden:yes}
  dimension: eval_loss {type: number}
  dimension: duration_ms {label:"Duration (ms)" type: number}
  dimension: learning_rate {type: number}
  measure: total_iterations {
    type: count
  }
  measure: loss {
    value_format_name: decimal_2
    type: sum
    sql:  ${loss_raw} ;;
  }
  measure: total_training_time {
    type: sum
    label:"Total Training Time (sec)"
    sql: ${duration_ms}/1000 ;;
    value_format_name: decimal_1
  }
  measure: average_iteration_time {
    type: average
    label:"Average Iteration Time (sec)"
    sql: ${duration_ms}/1000 ;;
    value_format_name: decimal_1
  }
}

##################################################
# ML 2 : Tree XGBOOST
##################################################

explore: future_purchase_model_tree_xgboost {}:
view: future_purchase_model_tree_xgboost {
  derived_table: {
    persist_for: "24 hours" # need to have persistence
    sql_create:
      CREATE OR REPLACE MODEL ${SQL_TABLE_NAME}
      OPTIONS(model_type='boosted_tree_classifier',
        booster_type = 'gbtree',
        num_parallel_tree = 1,
        max_iterations = 50,
        tree_method = 'hist',
        early_stop = false,
        subsample = 0.85,
        input_label_cols = ['predicted_will_purchase']
        ) AS
      SELECT
         * EXCEPT(id)
      FROM ${training_input.SQL_TABLE_NAME};;
  }
}

explore: model_evaluation_tree_xgboost {}
view: model_evaluation_tree_xgboost {
  derived_table: {
    sql: SELECT
          roc_auc,
            CASE
              WHEN roc_auc > .9 THEN 'good'
              WHEN roc_auc > .8 THEN 'fair'
              WHEN roc_auc > .7 THEN 'decent'
              WHEN roc_auc > .6 THEN 'not great'
              ELSE 'poor' END AS model_quality,
          log_loss,
          accuracy,
            CASE
              WHEN accuracy > .9 THEN 'good'
              WHEN accuracy > .8 THEN 'fair'
              WHEN accuracy > .7 THEN 'decent'
              WHEN accuracy > .6 THEN 'not great'
              ELSE 'poor' END AS model_accuracy,
         FROM ML.EVALUATE(MODEL ${future_purchase_model_tree_xgboost.SQL_TABLE_NAME},(SELECT * FROM ${testing_input.SQL_TABLE_NAME})) ;;
  }
  dimension: model_quality {}
  dimension: accuracy {type: number value_format_name:percent_2}
  dimension: log_loss {type: number}
  dimension: roc_auc {type: number}
}

explore: model_prediction_tree_xgboost {}
view: model_prediction_tree_xgboost {
  derived_table: {
    sql: SELECT * FROM ML.PREDICT(
          MODEL ${future_purchase_model_tree_xgboost.SQL_TABLE_NAME},
          (SELECT * FROM ${predict_input.SQL_TABLE_NAME}));;
  }

  dimension: predicted_will_purchase {type:string}
  dimension: id {
    type: string}
  dimension: country {
    type:string
    map_layer_name: countries
  }
  dimension: os {}
  dimension: is_mobile {}
  measure: id_count{
    type: count_distinct
    sql: ${id} ;;
  }
  dimension: pageviews {}
  measure: pageviews_sum {
    type: sum
    sql: ${pageviews} ;;}
  dimension: pk2_opportunity_id {hidden:yes}
  dimension: pk2_date {hidden:yes}
  dimension: result {type: number}
  dimension: predicted_result {type: number}
  dimension: renewal_prob {type: number sql:(SELECT prob FROM UNNEST(${TABLE}.predicted_result_probs) WHERE label=1);; value_format_name: percent_2}
  measure: count {type:count drill_fields: [account.name, renewal_prob, predicted_result, result]}
  measure: predicted_renewals {type:sum sql:${predicted_result};;}
  measure: predicted_nonrenewals {type:sum sql:1-${predicted_result};;}
  measure: ev_renewals {type:sum sql:${renewal_prob};; value_format_name:decimal_1}
  measure: actual_renewals {type:sum sql:${result};;}
  measure: actual_nonrenewals {type:sum sql:1-${result};;}
  measure: false_positives {
    type:count
    filters: {field: predicted_result value: "1"}
    filters: {field: result value:"0"}
    drill_fields: [account.name, renewal_prob, predicted_result, result]
  }
}

explore: roc_curve_tree_xgboost {}
view: roc_curve_tree_xgboost {
  derived_table: {
    sql: SELECT * FROM ml.ROC_CURVE(
        MODEL ${future_purchase_model_tree_xgboost.SQL_TABLE_NAME},
        (SELECT * FROM ${testing_input.SQL_TABLE_NAME}));;
  }
  dimension: threshold {
    type: number
    value_format_name: decimal_4
    link: {
      label: "Campaign List Creator"
      url: "/dashboards/202?Customer%20Propensity%20to%20Purchase=>{{ rendered_value | encode_uri }}"
      icon_url: "http://www.looker.com/favicon.ico"
    }
  }
  dimension: false_positive_rate {type: number}
  dimension: true_positives {type: number }
  dimension: false_positives {type: number}
  dimension: true_negatives {type: number}
  dimension: false_negatives {type: number }
  dimension: precision {
    type:  number
    value_format_name: percent_2
    sql:  ${true_positives} / NULLIF((${true_positives} + ${false_positives}),0);;
    description: "Equal to true positives over all positives. Indicative of how false positives are penalized. Set high to get no false positives"
  }
  measure: total_false_positives {
    type: sum
    sql: ${false_positives} ;;
  }
  measure: total_true_positives {
    type: sum
    sql: ${true_positives} ;;
  }
  dimension: threshold_accuracy {
    type: number
    value_format_name: percent_2
    sql:  1.0*(${true_positives} + ${true_negatives}) / NULLIF((${true_positives} + ${true_negatives} + ${false_positives} + ${false_negatives}),0);;
  }
}


##################################################
# ML 3 : DNN CLASSIFIER
##################################################

explore: future_purchase_model_dnn_classifier {}:
view: future_purchase_model_dnn_classifier {
  derived_table: {
    persist_for: "24 hours" # need to have persistence
    sql_create:
      CREATE OR REPLACE MODEL ${SQL_TABLE_NAME}
      OPTIONS(model_type='dnn_classifier',
        activation_fn = 'relu',
        batch_size = 16,
        dropout = 0.1,
        early_stop = false,
        hidden_units = [128, 128, 128],
        input_label_cols = ['predicted_will_purchase'],
        learn_rate=0.001,
        max_iterations = 50,
        optimizer = 'adagrad') AS
      SELECT
      * EXCEPT(id)
      FROM ${training_input.SQL_TABLE_NAME};;
  }
}

explore: model_evaluation_dnn_classifier {}
view: model_evaluation_dnn_classifier {
  derived_table: {
    sql: SELECT
          roc_auc,
            CASE
              WHEN roc_auc > .9 THEN 'good'
              WHEN roc_auc > .8 THEN 'fair'
              WHEN roc_auc > .7 THEN 'decent'
              WHEN roc_auc > .6 THEN 'not great'
              ELSE 'poor' END AS model_quality,
          log_loss,
          accuracy,
            CASE
              WHEN accuracy > .9 THEN 'good'
              WHEN accuracy > .8 THEN 'fair'
              WHEN accuracy > .7 THEN 'decent'
              WHEN accuracy > .6 THEN 'not great'
              ELSE 'poor' END AS model_accuracy,
         FROM ML.EVALUATE(MODEL ${future_purchase_model_dnn_classifier.SQL_TABLE_NAME},(SELECT * FROM ${testing_input.SQL_TABLE_NAME})) ;;
  }
  dimension: model_quality {}
  dimension: iteration {}
  dimension: fi_score {}
  dimension: recall {type: number value_format_name:percent_2}
  dimension: accuracy {type: number value_format_name:percent_2}
  dimension: f1_score {type: number value_format_name:percent_2}
  dimension: log_loss {type: number}
  dimension: roc_auc {type: number}
}

explore: model_prediction_dnn_classifier {}
view: model_prediction_dnn_classifier {
  derived_table: {
    sql: SELECT * FROM ML.PREDICT(
          MODEL ${future_purchase_model_dnn_classifier.SQL_TABLE_NAME},
          (SELECT * FROM ${predict_input.SQL_TABLE_NAME}));;
  }

  dimension: predicted_will_purchase {type:string}
  dimension: id {
    type: string}
  dimension: country {
    type:string
    map_layer_name: countries
  }
  dimension: os {}
  dimension: is_mobile {}
  measure: id_count{
    type: count_distinct
    sql: ${id} ;;
  }
  dimension: pageviews {}
  measure: pageviews_sum {
    type: sum
    sql: ${pageviews} ;;}
  dimension: pk2_opportunity_id {hidden:yes}
  dimension: pk2_date {hidden:yes}
  dimension: result {type: number}
  dimension: predicted_result {type: number}
  dimension: renewal_prob {type: number sql:(SELECT prob FROM UNNEST(${TABLE}.predicted_result_probs) WHERE label=1);; value_format_name: percent_2}
  measure: count {type:count drill_fields: [account.name, renewal_prob, predicted_result, result]}
  measure: predicted_renewals {type:sum sql:${predicted_result};;}
  measure: predicted_nonrenewals {type:sum sql:1-${predicted_result};;}
  measure: ev_renewals {type:sum sql:${renewal_prob};; value_format_name:decimal_1}
  measure: actual_renewals {type:sum sql:${result};;}
  measure: actual_nonrenewals {type:sum sql:1-${result};;}
  measure: false_positives {
    type:count
    filters: {field: predicted_result value: "1"}
    filters: {field: result value:"0"}
    drill_fields: [account.name, renewal_prob, predicted_result, result]
  }
}

explore: roc_curve_dnn_classifier {}
view: roc_curve_dnn_classifier {
  derived_table: {
    sql: SELECT * FROM ml.ROC_CURVE(
        MODEL ${future_purchase_model_dnn_classifier.SQL_TABLE_NAME},
        (SELECT * FROM ${testing_input.SQL_TABLE_NAME}));;
  }
  dimension: threshold {
    type: number
    value_format_name: decimal_4
    link: {
      label: "Campaign List Creator"
      url: "/dashboards/202?Customer%20Propensity%20to%20Purchase=>{{ rendered_value | encode_uri }}"
      icon_url: "http://www.looker.com/favicon.ico"
    }
  }
  dimension: recall {type: number value_format_name: percent_2}
  dimension: false_positive_rate {type: number}
  dimension: true_positives {type: number }
  dimension: false_positives {type: number}
  dimension: true_negatives {type: number}
  dimension: false_negatives {type: number }
  dimension: precision {
    type:  number
    value_format_name: percent_2
    sql:  ${true_positives} / NULLIF((${true_positives} + ${false_positives}),0);;
    description: "Equal to true positives over all positives. Indicative of how false positives are penalized. Set high to get no false positives"
  }
  measure: total_false_positives {
    type: sum
    sql: ${false_positives} ;;
  }
  measure: total_true_positives {
    type: sum
    sql: ${true_positives} ;;
  }
  dimension: threshold_accuracy {
    type: number
    value_format_name: percent_2
    sql:  1.0*(${true_positives} + ${true_negatives}) / NULLIF((${true_positives} + ${true_negatives} + ${false_positives} + ${false_negatives}),0);;
  }
  dimension: threshold_f1 {
    type: number
    value_format_name: percent_3
    sql: 2.0*${recall}*${precision} / NULLIF((${recall}+${precision}),0);;
  }
}

##################################################
# ML 3 : AUTOML CLASSIFIER
##################################################

explore: future_purchase_model_automl_classifier {}:
view: future_purchase_model_automl_classifier {
  derived_table: {
    persist_for: "24 hours" # need to have persistence
    sql_create:
      CREATE OR REPLACE MODEL ${SQL_TABLE_NAME}
      OPTIONS(model_type='dnn_classifier',
        activation_fn = 'relu',
        batch_size = 16,
        dropout = 0.1,
        early_stop = false,
        hidden_units = [128, 128, 128],
        input_label_cols = ['predicted_will_purchase'],
        learn_rate=0.001,
        max_iterations = 50,
        optimizer = 'adagrad') AS
      SELECT
      * EXCEPT(id)
      FROM ${training_input.SQL_TABLE_NAME};;
  }
}

explore: model_evaluation_automl_classifier {}
view: model_evaluation_automl_classifier {
  derived_table: {
    sql: SELECT
          roc_auc,
            CASE
              WHEN roc_auc > .9 THEN 'good'
              WHEN roc_auc > .8 THEN 'fair'
              WHEN roc_auc > .7 THEN 'decent'
              WHEN roc_auc > .6 THEN 'not great'
              ELSE 'poor' END AS model_quality,
          log_loss,
          accuracy,
            CASE
              WHEN accuracy > .9 THEN 'good'
              WHEN accuracy > .8 THEN 'fair'
              WHEN accuracy > .7 THEN 'decent'
              WHEN accuracy > .6 THEN 'not great'
              ELSE 'poor' END AS model_accuracy,
         FROM ML.EVALUATE(MODEL ${future_purchase_model_automl_classifier.SQL_TABLE_NAME},(SELECT * FROM ${testing_input.SQL_TABLE_NAME})) ;;
  }
  dimension: model_quality {}
  dimension: iteration {}
  dimension: fi_score {}
  dimension: recall {type: number value_format_name:percent_2}
  dimension: accuracy {type: number value_format_name:percent_2}
  dimension: f1_score {type: number value_format_name:percent_2}
  dimension: log_loss {type: number}
  dimension: roc_auc {type: number}
}

explore: model_prediction_automl_classifier {}
view: model_prediction_automl_classifier {
  derived_table: {
    sql: SELECT * FROM ML.PREDICT(
          MODEL ${future_purchase_model_automl_classifier.SQL_TABLE_NAME},
          (SELECT * FROM ${predict_input.SQL_TABLE_NAME}));;
  }

  dimension: predicted_will_purchase {type:string}
  dimension: id {
    type: string}
  dimension: country {
    type:string
    map_layer_name: countries
  }
  dimension: os {}
  dimension: is_mobile {}
  measure: id_count{
    type: count_distinct
    sql: ${id} ;;
  }
  dimension: pageviews {}
  measure: pageviews_sum {
    type: sum
    sql: ${pageviews} ;;}
  dimension: pk2_opportunity_id {hidden:yes}
  dimension: pk2_date {hidden:yes}
  dimension: result {type: number}
  dimension: predicted_result {type: number}
  dimension: renewal_prob {type: number sql:(SELECT prob FROM UNNEST(${TABLE}.predicted_result_probs) WHERE label=1);; value_format_name: percent_2}
  measure: count {type:count drill_fields: [account.name, renewal_prob, predicted_result, result]}
  measure: predicted_renewals {type:sum sql:${predicted_result};;}
  measure: predicted_nonrenewals {type:sum sql:1-${predicted_result};;}
  measure: ev_renewals {type:sum sql:${renewal_prob};; value_format_name:decimal_1}
  measure: actual_renewals {type:sum sql:${result};;}
  measure: actual_nonrenewals {type:sum sql:1-${result};;}
  measure: false_positives {
    type:count
    filters: {field: predicted_result value: "1"}
    filters: {field: result value:"0"}
    drill_fields: [account.name, renewal_prob, predicted_result, result]
  }
}

explore: roc_curve_automl_classifier {}
view: roc_curve_automl_classifier {
  derived_table: {
    sql: SELECT * FROM ml.ROC_CURVE(
        MODEL ${future_purchase_model_automl_classifier.SQL_TABLE_NAME},
        (SELECT * FROM ${testing_input.SQL_TABLE_NAME}));;
  }
  dimension: threshold {
    type: number
    value_format_name: decimal_4
    link: {
      label: "Campaign List Creator"
      url: "/dashboards/202?Customer%20Propensity%20to%20Purchase=>{{ rendered_value | encode_uri }}"
      icon_url: "http://www.looker.com/favicon.ico"
    }
  }
  dimension: recall {type: number value_format_name: percent_2}
  dimension: false_positive_rate {type: number}
  dimension: true_positives {type: number }
  dimension: false_positives {type: number}
  dimension: true_negatives {type: number}
  dimension: false_negatives {type: number }
  dimension: precision {
    type:  number
    value_format_name: percent_2
    sql:  ${true_positives} / NULLIF((${true_positives} + ${false_positives}),0);;
    description: "Equal to true positives over all positives. Indicative of how false positives are penalized. Set high to get no false positives"
  }
  measure: total_false_positives {
    type: sum
    sql: ${false_positives} ;;
  }
  measure: total_true_positives {
    type: sum
    sql: ${true_positives} ;;
  }
  dimension: threshold_accuracy {
    type: number
    value_format_name: percent_2
    sql:  1.0*(${true_positives} + ${true_negatives}) / NULLIF((${true_positives} + ${true_negatives} + ${false_positives} + ${false_negatives}),0);;
  }
  dimension: threshold_f1 {
    type: number
    value_format_name: percent_3
    sql: 2.0*${recall}*${precision} / NULLIF((${recall}+${precision}),0);;
  }
}
