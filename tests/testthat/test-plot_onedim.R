context("Test plot_onedim")

data("toy_tasks", package="dyntoy")

toy_tasks <- toy_tasks %>% group_by(toy_tasks$trajectory_type) %>% filter(row_number() == 1) %>% ungroup()

for (taski in seq_len(nrow(toy_tasks))) {
  task <- extract_row_to_list(toy_tasks, taski)

  test_that(paste0("Plot onedim in ", task$id), {
    g <- plot_onedim(task)
    expect_is(g, "ggplot")

    pdf("/dev/null")
    print(g)
    dev.off()
  })
}