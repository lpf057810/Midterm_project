pacman::p_load(
  dplyr,
  caret,
  ggplot2,
  lattice,
  knitr,
  broom,
  here
)

here::i_am(
  "subproject2/code/model.R"
)

absolute_path <- here::here("data/covid_sub.csv")
data<-read.csv(absolute_path,header = TRUE)

data_clean <- data %>% 
  filter(!is.na(ICU))

data_clean <- data_clean %>%
  mutate(CLASSIFIED =  ifelse(data_clean$CLASIFFICATION_FINAL >= 1 &
                                data_clean$CLASIFFICATION_FINAL <=3, 
                              "Positive", "Inconclusive")
  )

# encode categorical varibles

columns_to_encode <- names(data_clean)[sapply(data_clean, function(column) {
  all(c('Yes', 'No') %in% unique(column))
})]

data_clean <- data_clean %>%
  mutate(across(all_of(columns_to_encode), ~if_else(.x == 'Yes', 1, 0)))

data_clean <- data_clean %>%
  mutate(SEX = recode(SEX, 'female' = 1, 'male' = 0))

data_clean <- data_clean %>%
  mutate(CLASSIFIED = recode(CLASSIFIED, 'Positive' = 1, 'Inconclusive' = 0))

# add a new variable DIED to indicate if the patient died 

data_clean <- data_clean %>%
  mutate(DIED = if_else(!is.na(DATE_DIED), 1, 0))
# logistic regression
# PREGNANT PNEUMONIA COPD DIABETES CARDIOVASCULAR RENAL_CHRONIC SEX AGE CLASSIFIED DIED as predictive variables
new_df <- data_clean %>%
  select(PREGNANT, PNEUMONIA, COPD, DIABETES, CARDIOVASCULAR, RENAL_CHRONIC,SEX, AGE, CLASSIFIED, DIED, ICU)
new_df<-na.omit(new_df)

model <- glm(ICU ~ PREGNANT + PNEUMONIA + COPD + DIABETES + CARDIOVASCULAR + RENAL_CHRONIC + SEX + AGE + DIED, 
             data = new_df, 
             family = binomial)


# Model Summary
tidy_model <- tidy(model)
model_table <- kable(tidy_model, caption = "Table. Model Summary", digits = 4)

saveRDS(
  model_table,
  file = here::here("subproject2/output/model/model_table.rds")
)

# Model Diagnostics
qqplot_path <- here::here("subproject2/output/model/QQplot.png")
png(qqplot_path, width = 1600, height = 1200)
par(mfrow = c(2, 2))
plot(model)
dev.off()

# Making Predictions
new_df$predicted_probabilities <- predict(model, type = "response")
new_df$predicted_ICU_class <- ifelse(new_df$predicted_probabilities > 0.5, 1, 0)

# Confusion Matrix
confusion_matrix <- table(Predicted = new_df$predicted_ICU_class, Actual = new_df$ICU)
confusion_matrix<-kable(confusion_matrix,caption = "Confusion matrix")

saveRDS(
  confusion_matrix,
  file = here::here("subproject2/output/model/confusion_matrix.rds")
)

# upsampling
# Split the dataset into majority and minority classes
df_majority <- new_df %>% filter(ICU == 0)
df_minority <- new_df %>% filter(ICU == 1)

# Calculate how many times the minority class needs to be replicated
upsample_factor <- nrow(df_majority) / nrow(df_minority)

# Upsample the minority class
df_minority_upsampled <- df_minority %>% 
  slice(rep(1:n(), each = ceiling(upsample_factor))) %>%
  head(nrow(df_majority))  # Ensure equal size

# Combine the upsampled minority class with the original majority class
df_balanced <- bind_rows(df_majority, df_minority_upsampled)

# Shuffle the combined dataset to randomize the order of rows
set.seed(123)  # For reproducibility
df_balanced <- df_balanced[sample(nrow(df_balanced)), ]

# logistic regression
model_upsampled <- glm(ICU ~ PREGNANT + PNEUMONIA + COPD + DIABETES + CARDIOVASCULAR + RENAL_CHRONIC + SEX + AGE + CLASSIFIED + DIED, 
                       data = df_balanced, 
                       family = binomial)


# Model Summary
tidy_model <- tidy(model_upsampled)
model_upsampled_table <- kable(tidy_model, caption = "Table. Model_upsampled Summary", digits = 4)

saveRDS(
  model_upsampled_table,
  file = here::here("subproject2/output/model/model_upsampled_table.rds")
)

# Model Diagnostics
qqplot_path <- here::here("subproject2/output/model/model_upsampled.png")
png(qqplot_path, width = 1600, height = 1200)
par(mfrow = c(2, 2))
plot(model_upsampled)
dev.off()

# Predicting probabilities
df_balanced$predicted_probabilities <- predict(model_upsampled, type = "response")

# Binarizing predictions based on a 0.5 threshold
df_balanced$predicted_ICU_class <- ifelse(df_balanced$predicted_probabilities > 0.5, 1, 0)

# Creating a confusion matrix
confusion_matrix <- table(Predicted = df_balanced$predicted_ICU_class, Actual = df_balanced$ICU)
confusion_matrix_upsampled<-kable(confusion_matrix, caption = "Confusion matrix_upsampled")

saveRDS(
  confusion_matrix_upsampled,
  file = here::here("subproject2/output/model/confusion_matrix_upsampled.rds")
)

# Varible selection
# Null model with no predictors
null_model <- glm(ICU ~ 1, 
                  data = df_balanced, 
                  family = binomial)

stepwise_model <- step(null_model,
                       scope = list(lower = null_model, upper = model_upsampled),
                       direction = "both",
                       trace = FALSE) # Set trace=TRUE to see step-by-step details


summary(stepwise_model)
tidy_model <- tidy(stepwise_model)
stepwise_model_table <- kable(tidy_model, caption = "Table.Stepwise_model Summary", digits= 4)

saveRDS(
  stepwise_model_table,
  file = here::here("subproject2/output/model/stepwise_model_table.rds")
)

# Model Diagnostics
qqplot_path <- here::here("subproject2/output/model/stepwise_model.png")
png(qqplot_path, width = 1600, height = 1200)
par(mfrow = c(2, 2))
plot(stepwise_model)
dev.off()

# Predicting probabilities
df_balanced$predicted_probabilities_stepwise <- predict(stepwise_model, type = "response")

# Binarizing predictions based on a 0.5 threshold
df_balanced$predicted_ICU_class_stepwise <- ifelse(df_balanced$predicted_probabilities_stepwise > 0.5, 1, 0)

# Creating a confusion matrix
confusion_matrix <- table(Predicted = df_balanced$predicted_ICU_class_stepwise, Actual = df_balanced$ICU)
confusion_matrix_stepwise<-kable(confusion_matrix,caption = "Confusion matrix_stepwise")

# No Improvement
saveRDS(
  confusion_matrix_stepwise,
  file = here::here("subproject2/output/model/confusion_matrix_stepwise.rds")
)

