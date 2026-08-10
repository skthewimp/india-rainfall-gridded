suppressMessages({library(arrow); library(dplyr); library(lubridate); library(ggplot2); library(scales)})
df <- read_parquet("RF25_ind2025_rfp25.parquet")

daily <- df %>% group_by(date) %>%
  summarise(mean_mm = mean(rainfall_mm), .groups="drop") %>%
  mutate(date = as.Date(date))

# quick numeric sanity
cat("date range:", format(min(daily$date)), "to", format(max(daily$date)), "\n")
cat("n days:", nrow(daily), "\n")
mon <- daily %>% mutate(m=month(date)) %>% group_by(m) %>% summarise(mm=sum(mean_mm))
cat("monsoon share Jun-Sep of annual:",
    round(100*sum(mon$mm[mon$m %in% 6:9])/sum(mon$mm),1), "%\n")
peak <- daily %>% slice_max(mean_mm, n=1)
cat("peak day:", format(peak$date), peak$mean_mm, "mm\n")

teal <- "#1b7a7a"
p <- ggplot(daily, aes(date, mean_mm)) +
  annotate("rect", xmin=as.Date("2025-06-01"), xmax=as.Date("2025-09-30"),
           ymin=-Inf, ymax=Inf, fill="grey90") +
  geom_line(colour=teal, linewidth=0.5) +
  annotate("text", x=as.Date("2025-07-25"), y=Inf, label="Southwest monsoon\nJun-Sep",
           vjust=1.6, hjust=0.5, size=3.4, colour="grey40", lineheight=0.9) +
  scale_x_date(date_breaks="1 month", date_labels="%b") +
  scale_y_continuous(expand=expansion(mult=c(0,0.08))) +
  labs(title="India's 2025 rainfall follows the textbook monsoon curve",
       subtitle="All-India daily mean rainfall across IMD land grid cells (mm/day)",
       x=NULL, y=NULL,
       caption="Source: IMD 0.25° daily gridded rainfall, RF25_ind2025_rfp25 | ~4,964 land cells averaged") +
  theme_minimal(base_size=12) +
  theme(panel.grid.minor=element_blank(),
        panel.grid.major.x=element_blank(),
        plot.title=element_text(face="bold"),
        plot.caption=element_text(colour="grey55", hjust=0),
        plot.title.position="plot")
ggsave("sanity_daily_rainfall_2025.png", p, width=9, height=5, dpi=150, bg="white")
cat("saved sanity_daily_rainfall_2025.png\n")
