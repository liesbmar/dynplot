library(dynutils)
library(tidyverse)
library(dynwrap)

toy_tasks <- dyntoy::toy_tasks %>% group_by(trajectory_type) %>% filter(row_number() == 1) %>% ungroup()

task <- extract_row_to_list(toy_tasks, 1)

task <- root_trajectory(task, start_milestone_id = "M5")

library(ggraph)
library(tidygraph)

milestone_network <- task$milestone_network %>% mutate(edge_id = seq_len(n()))

milestone_graph <- milestone_network %>% as_tbl_graph()
igraph::layout_as_tree(milestone_graph) %>% plot()

#' @param task The trajectory
#' @param diag_offset The x-offset (percentage of the edge lenghts) between milestones
#' @export
generate_dendro_data <- function(task, diag_offset = 0.1) {
  # root if necessary
  if ("root_milestone_id" %in% names(task)) {
    root <- task$root_milestone_id
  } else {
    task <- dynwrap::root_trajectory(task, start_milestone_id = task$milestone_ids[[1]])
    root <- task$root_milestone_id
  }

  milestone_network <- task$milestone_network %>% mutate(edge_id = seq_len(n()))
  milestone_graph <- milestone_network %>% tidygraph::as_tbl_graph()

  # leaf positions
  leaves <- setdiff(milestone_network$to, milestone_network$from)
  node_order <- milestone_graph %>% igraph::dfs(root) %>% .$order %>% names # use dfs to find order of final nodes
  leaves <- leaves[order(match(leaves, node_order))]
  leaves_y <- set_names(seq_along(leaves), leaves)

  descendants <- map(task$milestone_ids, function(milestone_id) {intersect(leaves, names(igraph::dfs(milestone_graph, milestone_id, neimode="out", unreachable = F)$order))}) %>% set_names(task$milestone_ids)

  # calculate diag offset based on largest distances between root and leaf
  max_x <- igraph::distances(milestone_graph, root, leaves, weights=igraph::E(milestone_graph)$length) %>% max
  diag_offset <- max_x * diag_offset

  # now recursively go from root to leaves
  # each time adding the x and the y
  search <- function(from, milestone_positions = tibble(node_id = from, x = 0, y=mean(leaves_y[descendants[[from]]]))) {
    milestone_network_to <- milestone_network %>% filter(from %in% !!from, !to %in% milestone_positions$node_id)
    milestone_positions <- bind_rows(
      milestone_positions,
      tibble(
        node_id = milestone_network_to$to,
        x = milestone_positions$x[match(milestone_network_to$from, milestone_positions$node_id)] + milestone_network_to$length + diag_offset,
        y = map_dbl(milestone_network_to$to, ~mean(leaves_y[descendants[[.]]])),
        parent_node_id = milestone_network_to$from,
        edge_id = milestone_network_to$edge_id
      )
    )

    if (nrow(milestone_network_to) > 0) {
      milestone_positions <- search(milestone_network_to$to, milestone_positions)
    }

    milestone_positions
  }

  milestone_positions_to <- search(root)
  milestone_positions_from <- milestone_positions_to %>%
    filter(!is.na(parent_node_id)) %>%
    mutate(
      child_node_id = node_id,
      x = milestone_positions_to$x[match(parent_node_id, milestone_positions_to$node_id)] + diag_offset,
      node_id = paste0(parent_node_id, "-", node_id),
    )

  milestone_positions <- bind_rows(
    milestone_positions_to %>% mutate(node_type = "milestone"),
    milestone_positions_from %>% mutate(node_type = "fake_milestone")
  )

  milestone_tree_branches <- tibble(
    node_id_from = milestone_positions_from$node_id,
    node_id_to = milestone_positions_from$child_node_id,
    edge_id = milestone_positions_from$edge_id
  )

  milestone_tree_connections <- tibble(
    node_id_from = milestone_positions_from$parent_node_id,
    node_id_to = milestone_positions_from$node_id
  )

  milestone_tree_edges <- bind_rows(
    milestone_tree_branches,
    milestone_tree_connections
  ) %>%
    left_join(
      milestone_positions %>% select(node_id, x, y) %>% rename_all(~paste0(., "_from")),
      "node_id_from"
    ) %>%
    left_join(
      milestone_positions %>% select(node_id, x, y) %>% rename_all(~paste0(., "_to")),
      "node_id_to"
    )

  milestone_tree <- tidygraph::tbl_graph(milestone_positions, milestone_tree_edges %>% mutate(from = match(node_id_from, milestone_positions$node_id), to = match(node_id_to, milestone_positions$node_id)))


  # put cells on tree
  progressions <- task$progressions %>%
    group_by(cell_id) %>%
    arrange(percentage) %>%
    filter(row_number() == 1) %>%
    ungroup()

  cell_positions <- progressions %>%
    left_join(milestone_network %>% select(from, to, edge_id), c("from", "to")) %>% # get edge_ids
    left_join(milestone_tree_edges, "edge_id") %>% # add x and y positions
    mutate(
      x = x_from + (x_to - x_from) * percentage,
      y = y_from
    ) %>%
    mutate(y = y + vipor::offsetX(x, edge_id, method="quasirandom", width=0.2))

  lst(milestone_tree, milestone_positions, cell_positions)
}

plot_dendro <- function(task, grouping=NULL, groups=NULL) {
  dendro_data <- generate_dendro_data(task)

  filter_edges <- function(q = quo(is.na(x$edge_id))) {
    function(x) {x <- get_edges()(x); x[!!q, ]}
  }

  layout <- ggraph::create_layout(dendro_data$milestone_tree, "manual", node.position = dendro_data$milestone_positions)

  ggplot(layout) +
    ggraph::geom_edge_link(aes(linetype = node1.node_type, edge_width = node1.node_type), colour="grey") +
    ggraph::geom_edge_link(aes(xend = x + (xend-x)/2, alpha=ifelse(node1.node_type == "milestone", 0, 1)), arrow=arrow(type="closed"), colour="grey") + # arrow
    # ggraph::geom_node_label(aes(label=node_id)) +
    geom_point(aes(x, y), data=dendro_data$cell_positions) +
    ggraph::theme_graph() +
    ggraph::scale_edge_alpha_identity() +
    ggraph::scale_edge_linetype_manual(values=c("milestone"="solid", "fake_milestone"="solid"), guide="none") +
    ggraph::scale_edge_width_manual(values=c("milestone"=1, "fake_milestone"=3), guide="none")
}

