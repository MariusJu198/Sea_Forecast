# =========================================================================================================== #
#                       
#                                     This Tool executes the SEA_Forecast
#
#               
# =========================================================================================================== #

# ===================================== Load data and packages ============================================== #


cat("\014") 
graphics.off()  # clear all graphs
rm(list = ls()) # remove all files from your workspace

pacman::p_load(pacman, urca, vars, tsDyn,forecast,readxl,xts, ggfortify,stargazer, tseries, ggplot2, tidyr, caret,  dplyr, foreach, randomForest, kableExtra, keras, ModelMetrics, xlsx) #installing neccesary packages 

data <-read_excel("C:\\Users\\mariu\\OneDrive\\Skrivebord\\UNI\\8. semester\\Economic forecasting\\Project\\Data\\Processed\\Final.xlsx") #Change to your own directory

source("C:\\Users\\mariu\\OneDrive\\Skrivebord\\UNI\\8. semester\\Economic forecasting\\Project\\Code\\gw.test.R")

n <- nrow(data)


# ===================================== declare variables as time series ===================================== #

SIE <-ts(data$SIE, freq=12, start=1993)
CO2 <-ts(data$CO2, freq=12, start=1993)
SST <-ts(data$AT, freq=12, start=1993)
SL <-ts(data$GMSL, freq=12, start=1993)


# ===================================== Stationarity ===================================== #

fit.C02 <- tslm(CO2 ~ season)
summary(fit.C02)
residuals <- resid(fit.C02)
CO2_ds <- residuals
adf.test(CO2_ds)
kpss.test(CO2)

diff_CO2<-diff(CO2_ds)
kpss.test(diff_CO2)
#both tests support that CO2 is a difference stationary variable

fit.SST <- tslm(SST ~ season)
residuals <- resid(fit.SST)
SST_ds <- residuals

kpss.test(SST_ds, null=c("T"))
#AT is not trend stationary 


diff_SST<-diff(SST_ds)
kpss.test(diff_SST)
adf.test(diff_SST)
#Both tests support that AT is a difference stationary variable

fit.SL <- tslm(SL ~ season+trend)
summary(fit.SL)
residuals <- resid(fit.SL)
SL_ds <- residuals
kpss.test(SL_ds)
adf.test(SL_ds)

diff_SL<-diff(SL_ds)
kpss.test(diff_SL)
adf.test(diff_SL)
#Both tests support that SL is a difference stationary variable

fit.SIE <- tslm(SIE ~ season)
summary(fit.SIE)
residuals <- resid(fit.SIE)
SL_ds <- residuals




# ===================================== Data preperation and plotting ===================================== #

#deseasonalised data
ds_data <- data.frame(
  Month = 1:length(CO2_ds),  # Assuming the time series is monthly
  CO2 = CO2_ds,
  SST = SST_ds,
  SL= ts(SL_ds)
)

#stationary data 
stationary_data <- data.frame(
  Month = 1:length(diff_CO2),  # Assuming the time series is monthly
  CO2 = diff_CO2,
  SST= diff_SST,
  SL = diff_SL
)


# Reshape the dataframe for easier plotting
melted_data <- pivot_longer(ds_data, cols = -Month, names_to = "Variable", values_to = "Deseasonalized_Value")

# Plot using ggplot2
ggplot(melted_data, aes(x = Month, y = Deseasonalized_Value, color = Variable)) +
  geom_line() +
  labs(x = "Month", y = "Deseasonalized Value", color = "Variable") +
  ggtitle("Deseasonalized Time Series Plot") +
  theme_minimal() +
  facet_wrap(~ Variable, nrow = 4, scales = "free_y")  # Stacking plots vertically with free y-axis scales


# ===================================== Creating test and training data - stationary data ===================================== #

#Splitting up into a training, validation and test-set 
train_prop <-0.8 
test_prop <- 0.2

# Calculate the number of observations for each set
n <- length(diff_SL)
n_train <- round(train_prop * n)
n_test <- n - n_train

# Create training, validation, and testing datasets
set.seed(123)  # for reproducibility
train_data <- stationary_data[1:n_train,]
test_data <- stationary_data[(n_train+1):n,]



# ===================================== Rolling window forecast - stationary part ===================================== #

#Parameters for Random Forest 
lag_order <- 7
ntree <- 500


#fully  embedded data
SL_ts_full <- embed(stationary_data$SL, lag_order+1)
n_rf_train <- n_train-lag_order*(ncol(SL_ts_full)/(lag_order+1))

# = Number of windows and window size
w_size = n_train
n_windows = n_test


# = Rolling Window Loop = #
forecasts_s = foreach(i=1:n_windows, .combine = rbind) %do%{
  
  # = Select data for the window (in and out-of-sample) = #
  X_in = stationary_data[i:(w_size + i - 1), ] # = change to X[1:(w_size + i - 1), ] for expanding window
  X_out = stationary_data[w_size + i, ]

  # ARIMA model # 
  arima_model <- auto.arima(X_in$SL)
  f1 <- forecast(arima_model, h = 1)
  
  #reversing the differencing to compare to levels
  f2 <- f1$mean+ds_data$SL[297+i]

  # Random Forest 
  set.seed(2019)
  y_train <- SL_ts_full[i:(n_rf_train+i-1), 1]
  X_train <- SL_ts_full[i:(n_rf_train+i-1), -1]
  X_test <- SL_ts_full[n_rf_train+i-1, c(1:lag_order)]
  
  fit_rf <- randomForest(X_train, y_train, ntree=ntree)
  
  # predict using the test set
  f3 <- predict(fit_rf, X_test)
  
  #reversing the differencing to compare to levels
  f4 <- f3+ds_data$SL[297+i]
  
  
  
  return(c(f2, f4))
}


# =====================================       Testing for cointegration between SL and CO2   ===================================== #

model_CO2 <- tslm(ts(SL) ~ ts(CO2), data=ds_data)

residuals <- resid(model_CO2)

#testing for cointegration
plot(residuals)
adf_test<-ur.df(residuals, type="trend", selectlags = "AIC")
summary(adf_test)
pp.test(residuals)

#The test supports cointegration between the deseasonalised data. 


# ===================================== Creating test and training data - for cointegration data ===================================== #

#Splitting up into a training, validation and test-set 
train_prop <-0.8 
test_prop <- 0.2

# Calculate the number of observations for each set
n <- length(SL_ds)
n_train <- round(train_prop * n)
n_test <- n - n_train

# Create training, validation, and testing datasets
set.seed(123)  # for reproducibility
train_data <- ds_data[1:n_train,]
test_data <- ds_data[(n_train+1):n,]



# ===================================== Rolling window forecast - cointegration part ===================================== #

# = Number of windows and window size
w_size = n_train
n_windows = n_test

# = Rolling Window Loop = #
forecasts_ns = foreach(i=1:n_windows, .combine = rbind) %do%{
  
  # = Select data for the window (in and out-of-sample) = #
  X_in = ds_data[i:(w_size + i - 1), ] # = change to X[1:(w_size + i - 1), ] for expanding window
  X_out = ds_data[w_size + i, ]
  
  #  Simple Regression Model #
  m1 = lm(SL ~ CO2, data = X_in)
  f1 = predict(m1, X_out)
  
  # Combined model # 
  m2 <- lm(SL ~ SST + CO2, data=X_in)
  f2 <- predict(m2, X_out)
  
  # VECM model #
  
  VECM<-VECM(X_in[,c("SL", "CO2")], lag=6, r=1)
  f3 <- data.frame(predict(VECM, n.ahead=1))
  
  # Random Walk #
  f4 = tail(X_in$SL, 1)
  
  return(c(f1, f2, f3$SL, f4))
}

result_matrix<-data.frame(cbind(forecasts_s,forecasts_ns, test_data$SL, test_data$Month))

colnames(result_matrix) <- c("ARIMA", "RF", "LM1", "LM2", "VECM", "RW", "Actual", "Month")


# ===================================== Performance meassures ===================================== #

# Define the predictors (forecasts) and the outcome (actual)
predictors <- cbind(result_matrix[, 1:6])
outcome <- result_matrix$Actual


for (i in 1:length(predictors)){
  
  print(names(predictors)[i])
  print(accuracy(predictors[,i],x=outcome))
}


# ===================================== Significance test ===================================== #

# calculating residuals 
residuals_matrix <- matrix(NA, nrow = length(outcome), ncol = ncol(predictors))
for (i in 1:ncol(predictors)) {
  residuals_matrix[, i] <- outcome - predictors[, i]
}

colnames(residuals_matrix) <- c("ARIMA", "RF", "LM1", "LM2", "VECM", "RW")

dm_test_results <- matrix(NA, ncol(predictors), ncol(predictors))

colnames(dm_test_results) <- rownames(dm_test_results) <- colnames(residuals_matrix)

# Iterate over each pair of models
for (i in 1:ncol(predictors)) {
  for (j in 1:ncol(predictors)) {
    if (i != j) {  # Exclude comparison with itself
      # Perform Diebold-Mariano test for the ith and jth models
      dm_test_result <- dm.test(residuals_matrix[, i], residuals_matrix[, j], h = 1, alternative = "less")
      
      # Store the p-value in the results matrix
      dm_test_results[j, i] <- dm_test_result$p.value
    }
  }
}




#Output into a Table

result_df <- round(as.data.frame(dm_test_results),3)

result_df[is.na(result_df)] <- 1 

result_df$ARIMA <- ifelse(result_df$ARIMA < 0.01, 
                          paste0(result_df$ARIMA, " ***"),
                          ifelse(result_df$ARIMA <0.05,
                                 paste0(result_df$ARIMA, " **"),
                          ifelse(result_df$ARIMA <0.1, 
                                 paste0(result_df$ARIMA, " *"), result_df$ARIMA   
                          )
                          )
                          )

result_df$RF <- ifelse(result_df$RF < 0.01, 
                          paste0(result_df$RF, " ***"),
                          ifelse(result_df$RF <0.05,
                                 paste0(result_df$RF, " **"),
                                 ifelse(result_df$RF <0.1, 
                                        paste0(result_df$RF, " *"), result_df$RF  
                                 )
                          )
)

result_df$RW <- ifelse(result_df$RW  < 0.01, 
                       paste0(result_df$RW , " ***"),
                       ifelse(result_df$RW  <0.05,
                              paste0(result_df$RW , " **"),
                              ifelse(result_df$RW <0.1, 
                                     paste0(result_df$RW, " *"), result_df$RW  
                              )
                       )
)

result_df$VECM <- ifelse(result_df$VECM   < 0.01, 
                       paste0(result_df$VECM  , " ***"),
                       ifelse(result_df$VECM   <0.05,
                              paste0(result_df$VECM  , " **"),
                              ifelse(result_df$VECM  <0.1, 
                                     paste0(result_df$VECM , " *"), result_df$VECM   
                              )
                       )
)


#Change headers for a better description 
colnames(result_df) <-rownames(result_df) <- c("ARIMA", "Random Forrest", "Linear-Model 1", "Linear-Model 2", "Vector error correction", "Random Walk")

result_df[result_df==1] <- NA

formatted_table <- kable(result_df, format="html", digits=3, align =rep('l',7)) %>%  
  kable_styling(bootstrap_options = "striped", full_width=F) %>%
   add_header_above(c("Diebold Mariano Tests"=7)) %>%
   add_footnote("p values: *** for p<0.001, ** for p<0.05, * for p<0.1")

formatted_table <- gsub('<td>', '<td style="text-align: left;">', formatted_table)

 
### Doing Giacomini & White test of Predictive Ability 

#Testing whether the VECM estimator has greater predictive ability than the Arima estimator. This is rejected on a 5% significance, p=0,178
gw.test(result_matrix$VECM,result_matrix$ARIMA,result_matrix$Actual, T=74, tau=1, alternative="greater")

#Testing whether the LM1 model has greater predictive ability than the LM2 model. This is rejected on a 5% significance, p=0,1732
gw.test(result_matrix$LM2,result_matrix$LM1,result_matrix$Actual, T=74, tau=1, alternative="greater")


#Clark & West 
#linear model
temp1 <- dm_cw(residuals_matrix[,c("LM1")],residuals_matrix[,c("LM2")])

#ARIMA and VECM model
temp2 <- dm_cw(residuals_matrix[,c("ARIMA")],residuals_matrix[,c("VECM")])


# ===================================== Creating an excel file for reference ===================================== #

# Specify the file path for the Excel file
file_path <- "result_matrix.xlsx"  # Adjust the file name as needed

# Write the result matrix to an Excel file
write.xlsx(result_matrix, file_path, row.names = FALSE)




















