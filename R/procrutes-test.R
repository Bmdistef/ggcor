#' Procrutes test for dissimilarity matrices
#' @description Perform procrutes test quickly and tidy up the data to
#' data frame.
#' @param spec,env data frame object.
#' @param group vector for rows grouping.
#' @param procrutes.fun string, name of procrutes test function.
#'    \itemize{
#'      \item{\code{"protest"} will use \code{vegan::protest} (default).}
#'      \item{\code{"procuste.randtest"} will use \code{ade4::procuste.randtest}.}
#'      \item{\code{"procuste.rtest"} will use \code{ade4::procuste.rtest}.}
#'   }
#' @param spec.select,env.select NULL (default), numeric or character vector index of columns.
#' @param spec.pre.fun,env.pre.fun string, function name of transform the input data.
#' @param spec.pre.params,env.pre.params list, extra parameters for \code{spec/env.pre.fun}.
#' @param ... extra params for \code{procrutes.fun}.
#' @return a data frame.
#' @importFrom vegan protest
#' @importFrom ade4 procuste.randtest procuste.rtest
#' @importFrom dplyr %>% mutate
#' @importFrom purrr map map2 pmap_dfr
#' @rdname procrutes_test
#' @examples \dontrun{
#' library(vegan)
#' data("varespec")
#' data("varechem")
#' procrutes_test(varespec, varechem)
#' procrutes_test(varespec, varechem, procrutes.fun = "procuste.randtest")
#' procrutes_test(varespec, varechem,
#'             spec.select = list(spec01 = 1:6, spec02 = 7:12))
#' procrutes_test(varespec, varechem, spec.pre.fun = "mono_mds",
#'             spec.select = list(spec01 = 1:6, spec02 = 7:12),
#'             env.select = list(env01 = 1:4, env02 = 5:14))
#' set.seed(20191224)
#' sam_grp <- sample(paste0("sample", 1:3), 24, replace = TRUE)
#' fortify_procrutes(varespec, varechem, group = sam_grp)
#' }
#' @seealso \code{\link[vegan]{protest}}, \code{\link[ade4]{procuste.rtest}},
#' \code{\link[ade4]{procuste.randtest}}.
#' @author Houyun Huang, Lei Zhou, Jian Chen, Taiyun Wei
#' @export
fortify_procrutes <- function(spec,
                              env,
                              group = NULL,
                              ...)
{
  if(!is.data.frame(spec))
    spec <- as.data.frame(spec)
  if(!is.data.frame(env))
    env <- as.data.frame(env)
  if(nrow(spec) != nrow(env)) {
    stop("'spec' must have the same rows as 'env'.", call. = FALSE)
  }

  if(!is.null(group)) {
    if(length(group) != nrow(spec))
      stop("Length of 'group' and rows of 'spec' must be same.", call. = FALSE)
    spec <- split(spec, group, drop = FALSE)
    env <- split(env, group, drop = FALSE)

    df <- suppressMessages(
      purrr::pmap_dfr(list(spec, env, as.list(names(spec))),
                      function(.spec, .env, .group) {
                        procrutes_test(.spec, .env, ...) %>%
                          dplyr::mutate(.group = .group)
                      })
    )
  } else {
    df <- procrutes_test(spec, env, ...)
  }
  grouped <- if(!is.null(group)) TRUE else FALSE
  attr(df, "grouped") <- grouped
  df
}

#' @rdname procrutes_test
#' @export
procrutes_test <- function(spec,
                           env,
                           procrutes.fun = "protest",
                           spec.select = NULL, # a list of index vector
                           env.select = NULL,
                           spec.pre.fun = "identity",
                           spec.pre.params = list(),
                           env.pre.fun = spec.pre.fun,
                           env.pre.params = spec.pre.params,
                           ...)
{
  procrutes.fun <- match.arg(procrutes.fun, c("protest", "procuste.randtest", "procuste.rtest"))

  if(!is.data.frame(spec))
    spec <- as.data.frame(spec)
  if(!is.data.frame(env))
    env <- as.data.frame(env)
  if(nrow(spec) != nrow(env)) {
    stop("'spec' must have the same rows as 'env'.", call. = FALSE)
  }

  if(!is.list(spec.select) && !is.null(spec.select))
    stop("'spec.select' needs a list or NULL.", call. = FALSE)
  if(!is.list(env.select) && !is.null(env.select))
    stop("'env.select' needs a list or NULL.", call. = FALSE)
  if(is.null(spec.select)) {
    spec.select <- list(spec = 1:ncol(spec))
  }

  if(is.null(env.select)) {
    env.select <- as.list(setNames(1:ncol(env), names(env)))
  }
  spec.select <- make_list_names(spec.select, "spec")
  env.select <- make_list_names(env.select, "env")
  spec.name <- rep(names(spec.select), each = length(env.select))
  env.name <- rep(names(env.select), length(spec.select))
  spec <- purrr::map(spec.select, function(.x) {
    subset(spec, select = .x, drop = FALSE)})
  env <- purrr::map(env.select, function(.x) {
    subset(env, select = .x, drop = FALSE)})

  rp <- purrr::map2(spec.name, env.name, function(.x, .y) {
    .x <- do.call(spec.pre.fun, modifyList(list(spec[[.x]]), spec.pre.params))
    .y <- do.call(env.pre.fun, modifyList(list(env[[.y]]), env.pre.params))

    if(procrutes.fun != "protest") {
      if(!is.data.frame(.x)) {
        .x <- as.data.frame(as.matrix(.x))
      }
      if(!is.data.frame(.y)) {
        .y <- as.data.frame(as.matrix(.y))
      }
    }

    switch (procrutes.fun,
            protest           = vegan::protest(.x, .y, ...),
            procuste.randtest = ade4::procuste.randtest(.x, .y, ...),
            procuste.rtest    = ade4::procuste.rtest(.x, .y, ...),
    )
  }) %>% extract_procrutes(procrutes.fun)

  structure(.Data = tibble::tibble(spec = spec.name,
                                   env = env.name,
                                   r = rp$r,
                                   p.value = rp$p.value),
            grouped = FALSE,
            class = c("pro_tbl", "tbl_df", "tbl", "data.frame"))
}

#' Helper functions for procrutes test
#' @description \code{mono_mds} is used to transform data by \code{\link[vegan]{monoMDS}},
#' and \code{dudi_pca} is used to transform data by \code{\link[ade4]{dudi.pca}}.
#' @param x a data frame.
#' @param method the distance measure to be used.
#' @param ... extra parameters
#' @return a matrix.
#' @rdname procrutes_helper
#' @seealso \code{\link[vegan]{vegdist}}, \code{\link[vegan]{monoMDS}},
#' \code{\link[ade4]{dudi.pca}}.
#' @author Houyun Huang, Lei Zhou, Jian Chen, Taiyun Wei
#' @export
mono_mds <- function(x,
                     method="bray",
                     ...) {
  d <- vegan::vegdist(x, method = method)
  vegan::monoMDS(d, ...)
}
#' @rdname procrutes_helper
#' @author Houyun Huang, Lei Zhou, Jian Chen, Taiyun Wei
#' @export
dudi_pca <- function(x, ...) {
  pca <- ade4::dudi.pca(df = x, scannf = FALSE, ...)
  pca$tab
}

#' @importFrom purrr map_dbl
#' @noRd
extract_procrutes <- function(x, .f = "procrutes") {
  .f <- match.arg(.f, c("protest", "procuste.randtest", "procuste.rtest"))
  if(.f == "protest") {
    r <- purrr::map_dbl(x, `[[`, "t0")
    p.value <- purrr::map_dbl(x, `[[`, "signif")
  } else {
    r <- purrr::map_dbl(x, `[[`, "obs")
    p.value <- purrr::map_dbl(x, `[[`, "pvalue")
  }
  list(r = r, p.value = p.value)
}
