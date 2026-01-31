import argparse
import pandas as pd
from io import BytesIO
import boto3
import duckdb
import numpy as np
import gc
import catboost
import shap
import os
from botocore.exceptions import ClientError

# argument parsing
parser = argparse.ArgumentParser(description='Process data for a specified cohort.')
parser.add_argument('cohort', type=str, help='Cohort identifier to process')
args = parser.parse_args()

duckdb.sql("CREATE SECRET secret2 (TYPE S3, PROVIDER CREDENTIAL_CHAIN);")

# Verify S3 access
duckdb.sql("CALL load_aws_credentials();")

# Define cohort and S3 paths
cohort = args.cohort
s3_bucket = "pgx-repository"
s3_prefix = f"ade-risk-model/Step5_Time_to_Event_Model/2_polypharmacy_effects_removed/{cohort}"
train_input_path = f"s3://{s3_bucket}/{s3_prefix}/train/*.parquet"
test_input_path = f"s3://{s3_bucket}/{s3_prefix}/test/*.parquet"


# Read and transform data: Filter by polypharmacy range
train_df = duckdb.sql(f"""
    SELECT mi_person_key, drug_name_index, standardized_drug_name, activity_count, label, drug_date
    FROM read_parquet('{train_input_path}')
    WHERE polypharmacy > 7
    ORDER BY mi_person_key, drug_date
""").df()

test_df = duckdb.sql(f"""
    SELECT mi_person_key, drug_name_index, standardized_drug_name, activity_count, label, drug_date
    FROM read_parquet('{test_input_path}')
    WHERE polypharmacy > 7
    ORDER BY mi_person_key, drug_date
""").df()

print("Train and test datasets successfully loaded, transformed, and sorted.")

# Grouping variable
group_id = train_df['mi_person_key']
test_group_id = test_df['mi_person_key']

# Feature columns
feature_names = ['drug_name_index', 'activity_count']
categorical_features = ['drug_name_index']

# Ensure categorical features are in the correct format
train_df[categorical_features] = train_df[categorical_features].astype(str)
test_df[categorical_features] = test_df[categorical_features].astype(str)

# Categorical feature indices
cat_feature_indices = [feature_names.index(f) for f in categorical_features]

# Prepare the CatBoost Pool object, including the group_id for grouping
train_pool = catboost.Pool(
    data=train_df[feature_names], 
    label=train_df['label'],
    group_id=group_id, 
    cat_features=cat_feature_indices
  )

# Prepare the CatBoost Pool object, including the group_id for grouping
test_pool = catboost.Pool(
    data=test_df[feature_names], 
    label=test_df['label'],
    group_id=test_group_id, 
    cat_features=cat_feature_indices
  )
  
print("CatBoost Pools successfully loaded.")

session = boto3.Session()
s3 = session.client('s3')

s3_bucket = "pgx-repository"
seeds = [3, 24, 18, 17, 19, 11, 38, 74, 35, 90]
model_series = 9000  # Start model number tracker
model_type = "high_polypharmacy"

for seed in seeds:
    native_key = f"ade-risk-model/Step5_Time_to_Event_Model/4_models/{cohort}/local/{model_type}/model_{model_series}"

    # Check if model already exists in S3
    try:
        s3.head_object(Bucket=s3_bucket, Key=native_key)
        print(f"Model {model_series} already exists in S3, skipping training...")
        model_series += 1  # Increment model number
        continue  # Skip to the next seed
    except ClientError as e:
        if e.response['Error']['Code'] == "404":
            print(f"Model {model_series} not found in S3, proceeding with training...")
        else:
            raise  # If it's another error, raise it

    print(f"Training Model {model_series} with seed {seed}")

    # Train the CatBoost model
    local_model = catboost.CatBoostClassifier(
        iterations=100,
        depth=6,
        learning_rate=0.1,
        random_seed=seed
    )
    local_model.fit(train_pool)

    # Save and upload the model
    native_model_path = f"local_native_model_{model_series}"
    local_model.save_model(native_model_path)
    s3.upload_file(native_model_path, s3_bucket, native_key)
    os.remove(native_model_path)  # Remove local file after upload
    print(f"Model {model_series} uploaded to S3 at {native_key}")

    # Compute SHAP values using CatBoost's native method
    shap_values = local_model.get_feature_importance(
        data=train_pool,
        type='ShapValues',
        prettified=False
    )

    # Clear model from memory
    del local_model
    gc.collect()

    # Extract SHAP values for features (excluding the last column which is the expected value)
    shap_values = np.array(shap_values[:, :-1])
    shap_values_df = pd.DataFrame(
        shap_values, columns=[f"{col}_shap_value" for col in feature_names]
    )

    # Free memory
    gc.collect()

    # Merge SHAP values with features
    X_data = train_df[feature_names].reset_index(drop=True)
    train_shap_df = pd.concat([X_data, shap_values_df], axis=1)

    # Merge with drug information
    drug_info = train_df[['standardized_drug_name', 'drug_name_index']].drop_duplicates()
    train_shap_df = drug_info.merge(train_shap_df, on='drug_name_index', how='left')

    # Remove rows where all SHAP values are 0
    shap_values_df_filtered = train_shap_df[(train_shap_df[feature_names] != 0).all(axis=1)]

    # Perform aggregation in DuckDB
    conn = duckdb.connect()
    conn.register('shap_df', shap_values_df_filtered)

    aggregated_shap = conn.execute("""
        SELECT standardized_drug_name, 
               drug_name_index, 
               AVG(drug_name_index_shap_value) AS avg_shap_value
        FROM shap_df
        WHERE drug_name_index IS NOT NULL
        GROUP BY standardized_drug_name, drug_name_index
    """).fetchdf()

    conn.close()  # Close DuckDB connection

    # Save and upload aggregated SHAP values
    shap_csv_path = f"aggregated_shap_values_{cohort}_{model_series}.csv"
    aggregated_shap.to_csv(shap_csv_path, index=False)
    shap_s3_key = f"ade-risk-model/Step5_Time_to_Event_Model/5_feature_importances/{cohort}/{model_type}/aggregated_shap_values_{model_series}.csv"
    s3.upload_file(shap_csv_path, s3_bucket, shap_s3_key)
    os.remove(shap_csv_path)  # Remove local file after upload
    print(f"Aggregated SHAP values uploaded to S3 at {shap_s3_key}")

    # Free memory from final DataFrame
    del aggregated_shap
    gc.collect()

    # Increment model counter
    model_series += 1

print("All models trained and uploaded successfully!")
