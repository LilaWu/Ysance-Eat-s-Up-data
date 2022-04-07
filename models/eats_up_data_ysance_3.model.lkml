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
  join: model_prediction {
    relationship: one_to_one
    type: inner
    sql_on: ${model_prediction.id} = ${full_data.id} ;;
  }
}


view: full_data {
  derived_table:{
    sql:
       SELECT
          IF(totals.transactions IS NULL, 0, 1) AS predicted_will_purchase,
          IFNULL(device.operatingSystem, "") AS os,
          device.isMobile AS is_mobile,
          IFNULL(geoNetwork.country, "") AS country,
          IFNULL(totals.pageviews, 0) AS pageviews,
          date AS date,
          fullvisitorid AS id
        FROM
          `bigquery-public-data.google_analytics_sample.ga_sessions_*`
        WHERE
          _TABLE_SUFFIX BETWEEN '20160801' AND '20170801'
        ;;
  }


  dimension: id {}

  dimension: predicted_will_purchase {
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
    sql: SELECT * FROM ${full_data.SQL_TABLE_NAME} WHERE date BETWEEN '20160801' AND '20170630';;
  }
}

explore: testing_input {}
view: testing_input {
  derived_table: {
    sql: SELECT * FROM ${full_data.SQL_TABLE_NAME} WHERE date BETWEEN '20170701' AND '20170801' ;;
  }
}

explore: future_purchase_model {}:
view: future_purchase_model {
  derived_table: {
    persist_for: "24 hours" # need to have persistence
    sql_create:
      CREATE OR REPLACE MODEL ${SQL_TABLE_NAME}
      OPTIONS(model_type='logistic_reg'
        , labels=['Predicted_will_purchase']
        , min_rel_progress = 0.005
        , max_iterations = 40
        ) AS
      SELECT
         * EXCEPT(id)
      FROM ${training_input.SQL_TABLE_NAME};;
  }
}

explore: model_evaluation {}
view: model_evaluation {
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
         FROM ML.EVALUATE(MODEL ${future_purchase_model.SQL_TABLE_NAME},(SELECT * FROM ${testing_input.SQL_TABLE_NAME})) ;;
  }
  dimension: model_quality {}
  dimension: log_loss {}
  dimension: accuracy {}
}


explore: model_prediction {}:
view: model_prediction {
  derived_table: {
    sql: SELECT * FROM ML.PREDICT(
          MODEL ${future_purchase_model.SQL_TABLE_NAME},
          (SELECT * FROM ${full_data.SQL_TABLE_NAME}));;
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

}
