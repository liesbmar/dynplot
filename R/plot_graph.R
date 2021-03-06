#' Plot a trajectory and cellular positions as a graph
#'
#' @inheritParams dynwrap::calculate_trajectory_dimred
#' @inheritParams add_cell_coloring
#' @inheritParams add_milestone_coloring
#' @inheritParams plot_dimred
#' @param transition_size The size of the transition lines between milestones.
#' @param milestone_size The size of milestones.
#' @param arrow_length length of the arrow.
#' @param plot_milestones Whether to plot the milestones.
#'
#'
#' @importFrom grid arrow unit
#' @importFrom ggrepel geom_label_repel
#'
#' @aliases plot_default
#'
#' @keywords plot_trajectory
#'
#' @include add_coloring.R
#'
#' @export
#'
#' @examples
#' data(example_disconnected)
#' plot_graph(example_disconnected)
#' plot_graph(example_disconnected, color_cells = "pseudotime")
#' plot_graph(
#'   example_disconnected,
#'   color_cells = "grouping",
#'   grouping = dynwrap::group_onto_nearest_milestones(example_disconnected)
#' )
#'
#' data(example_tree)
#' plot_graph(example_tree)
plot_graph <- dynutils::inherit_default_params(
  list(add_cell_coloring, add_milestone_coloring),
  function(
    trajectory,
    color_cells,
    color_milestones,
    grouping,
    groups,
    feature_oi,
    pseudotime,
    expression_source,
    milestones,
    milestone_percentages,
    transition_size = 3,
    milestone_size = 5,
    arrow_length = grid::unit(1, "cm"),
    label_milestones = dynwrap::is_wrapper_with_milestone_labelling(trajectory),
    plot_milestones = FALSE,
    adjust_weights = FALSE
  ) {
    # make sure a trajectory was provided
    testthat::expect_true(dynwrap::is_wrapper_with_trajectory(trajectory))

    # TODO: 'milestones', in this function, is both used as the colouring of the cells (which could be from a different trajectory),
    # and plotting the milestones in the same dimred as the cells.
    # it's so confusing

    # check whether object has already been graph-dimredded
    dimred_traj <- calculate_trajectory_dimred(trajectory, adjust_weights = adjust_weights)

    # check milestones, make sure it's a data_frame
    milestones <- check_milestones(trajectory, milestones, milestone_percentages = milestone_percentages)

    # add coloring of milestones if not present
    milestones <- add_milestone_coloring(milestones, color_milestones)

    # get information of cells
    cell_positions <- dimred_traj$cell_positions
    cell_coloring_output <- add_cell_coloring(
      cell_positions = cell_positions,
      color_cells = color_cells,
      trajectory = trajectory,
      grouping = grouping,
      groups = groups,
      feature_oi = feature_oi,
      expression_source = expression_source,
      pseudotime = pseudotime,
      color_milestones = color_milestones,
      milestones = milestones,
      milestone_percentages = milestone_percentages
    )

    cell_positions <- cell_coloring_output$cell_positions
    color_scale <- cell_coloring_output$color_scale

    # get trajectory dimred
    # add coloring of milestones only if milestone percentages are not given
    milestone_positions <- dimred_traj$milestone_positions
    if (cell_coloring_output$color_cells == "milestone") {
      milestone_positions <- left_join(milestone_positions, milestones, "milestone_id")
    } else {
      milestone_positions$color <- NA
    }

    # get information of segments
    dimred_segments <- dimred_traj$edge_positions

    # plot the topology
    plot <-
      ggplot() +
      theme(legend.position = "none") +

      # Divergence gray backgrounds
      geom_polygon(
        aes(x = comp_1, y = comp_2, group = triangle_id),
        dimred_traj$divergence_polygon_positions,
        fill = "#eeeeee"
      ) +

      # Divergence dashed lines
      geom_segment(
        aes(x = comp_1_from, xend = comp_1_to, y = comp_2_from, yend = comp_2_to),
        dimred_traj$divergence_edge_positions,
        colour = "darkgray",
        linetype = "dashed"
      )

    if (plot_milestones) {
      plot <- plot +
        geom_point(aes(comp_1, comp_2), size = 12, data = milestone_positions, colour = "gray")
    }

      # Transition gray border
    plot <- plot +
      geom_segment(
        aes(x = comp_1_from, xend = comp_1_to, y = comp_2_from, yend = comp_2_to),
        dimred_segments,
        size = transition_size + 2,
        colour = "grey"
      ) +

      # Transition halfway arrow
      geom_segment(
        aes(x = comp_1_from, xend = comp_1_from + (comp_1_to - comp_1_from) / 1.5, y = comp_2_from, yend = comp_2_from + (comp_2_to - comp_2_from) / 1.5),
        dimred_segments %>% filter(directed, length > 0),
        size = 1,
        colour = "grey",
        arrow = arrow(length = arrow_length, type = "closed")
      ) +

      # Transition white tube
      geom_segment(
        aes(x = comp_1_from, xend = comp_1_to, y = comp_2_from, yend = comp_2_to),
        dimred_segments,
        size = transition_size,
        colour = "white"
      )

    if (plot_milestones) {
      plot <- plot +
        # Milestone white bowl
        geom_point(aes(comp_1, comp_2), size = 10, data = milestone_positions, colour = "white") +

        # Milestone fill
        geom_point(aes(comp_1, comp_2, colour = color), size = 8, data = milestone_positions %>% filter(!is.na(color)), alpha = .5)
    }

    # plot the cells

    plot <- plot +
      # Cell borders
      geom_point(aes(comp_1, comp_2), size = 2.5, color = "black", data = cell_positions) +

      # Cell fills
      geom_point(aes(comp_1, comp_2, color = color), size = 2, data = cell_positions) +

      color_scale +
      theme_graph() +
      theme(legend.position = "bottom", plot.title = element_text(hjust = 0.5))

    # label milestones
    label_milestones <- get_milestone_labelling(trajectory, label_milestones)

    if (length(label_milestones)) {
      milestone_labels <- milestone_positions %>%
        mutate(label = label_milestones[milestone_id]) %>%
        filter(!is.na(label))

      plot <- plot + geom_label(aes(comp_1, comp_2, label = label), data = milestone_labels)
    }

    plot
  }
)

#' @export
plot_default <- plot_graph
