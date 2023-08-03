defmodule EctoShorts.CommonFilters do
  @moduledoc """
  This modules main purpose is to house a collection of common schema filters
  and functionality to be included in params -> filters

  Common filters available include

  - `preload` - Preloads fields onto the query results
  - `start_date` - Query for items inserted after this date
  - `end_date` - Query for items inserted before this date
  - `before` - Get items with ID's before this value
  - `after` - Get items with ID's after this value
  - `ids` - Get items with a list of ids
  - `first` - Gets the first n items
  - `last` - Gets the last n items
  - `limit` - Gets the first n items
  - `offset` - Offsets limit by n items
  - `order_by` - orders the results in desc or asc order
  - `search` - ***Warning:*** This requires schemas using this to have a `&by_search(query, val)` function

  ```elixir
  CommonFilters.convert_params_to_filter(User, %{first: 10})
  CommonFilters.convert_params_to_filter(User, %{ids: [1, 2, 3, 4]})
  CommonFilters.convert_params_to_filter(User, %{order_by: {:desc, :email_updated_at})
  ```

  You are also able to filter on any natural field of a model, as well as use

  - gte/gt
  - lte/lt
  - like/ilike
  - is_nil/not(is_nil)

  ```elixir
  CommonFilters.convert_params_to_filter(User, %{name: "Billy"})
  CommonFilters.convert_params_to_filter(User, %{name: %{ilike: "steve"}})
  CommonFilters.convert_params_to_filter(User, %{name: %{age: %{gte: 18, lte: 30}}})
  CommonFilters.convert_params_to_filter(User, %{name: %{is_banned: %{!=: nil}}})
  CommonFilters.convert_params_to_filter(User, %{name: %{is_banned: %{==: nil}}})
  CommonFilters.convert_params_to_filter(User, %{name: %{balance: %{!=: 0}}})
  ```

  CommonFilters also supports limited fragment modifiers of natural fields:

  - :lower for "lower(?)"
  - :upper for "lower(?)"

  ```elixir
  CommonFilters.convert_params_to_filter(User, %{name: {:lower, "billy"}})
  CommonFilters.convert_params_to_filter(User, %{name: {:upper, "BILLY"}})
  CommonFilters.convert_params_to_filter(User, %{name: %{!=: {:lower, "billy"}}})
  ```
  """

  alias EctoShorts.QueryBuilder

  @common_filters QueryBuilder.Common.filters()

  @doc "Converts filter params into a query"
  @spec convert_params_to_filter(
    queryable :: Ecto.Queryable.t(),
    params :: Keyword.t | map
  ) :: Ecto.Query.t
  def convert_params_to_filter(query, params) when params === %{}, do: query
  def convert_params_to_filter(query, params) when is_map(params) do
    convert_params_to_filter(query, Map.to_list(params))
  end

  def convert_params_to_filter(query, params) do
    params
      |> configure_preload
      |> ensure_last_is_final_filter
      |> Enum.reduce(query, &create_schema_filter/2)
  end

  def create_schema_filter({filter, val}, query) when filter in @common_filters do
    QueryBuilder.create_schema_filter(QueryBuilder.Common, {filter, val}, query)
  end

  def create_schema_filter({filter, val}, query) do
    QueryBuilder.create_schema_filter(QueryBuilder.Schema, {filter, val}, query)
  end

  defp ensure_last_is_final_filter(params) do
    if Keyword.has_key?(params, :last) do
      params
        |> Keyword.delete(:last)
        |> Kernel.++([last: params[:last]])
    else
      params
    end
  end

  def configure_preload(params) do
    case Keyword.get(params, :preload) do
      nil ->
        params
      preload ->
        formated_preload = traverse_preload(preload, [])
        params
          |> Keyword.delete(:preload)
          |> Kernel.++([preload: formated_preload])
    end
  end

  def traverse_preload(preload, relationship_list) when is_list(preload) do
    Enum.reduce(preload, [], fn p, acc ->
      resolve_preload(p, relationship_list, acc)
    end)
  end

  def traverse_preload(preload, relationship_list) do
    traverse_preload([preload], relationship_list)
  end

  def resolve_preload({k, {[binding_name: name], v}}, relationship_list, acc) do
    relationship_list = relationship_list ++ [k]
    [{k, {EctoShorts.QueryBuilder.Schema.dynamic_preload(name), traverse_preload(v, relationship_list)}} | acc]
  end

  def resolve_preload({k, {:ecto_shorts_binding, v}}, relationship_list, acc) do
    relationship_list = relationship_list ++ [k]
    [{k, {relationship_list |> build_ecto_shorts_binding() |> EctoShorts.QueryBuilder.Schema.dynamic_preload(), traverse_preload(v, relationship_list)}} | acc]
  end

  def resolve_preload({k, :ecto_shorts_binding}, relationship_list, acc) do
    relationship_list = relationship_list ++ [k]
    [{k, {relationship_list |> build_ecto_shorts_binding() |> EctoShorts.QueryBuilder.Schema.dynamic_preload()}} | acc]
  end

  def resolve_preload({k, [binding_name: name]}, _relationship_list, acc) do
    [{k, {EctoShorts.QueryBuilder.Schema.dynamic_preload(name)}} | acc]
  end

  def resolve_preload({k, v}, relationship_list, acc) do
    relationship_list = relationship_list ++ [k]
    [{k, traverse_preload(v, relationship_list)} | acc]
  end

  def resolve_preload(p, _relationship_list, acc) do
    [p | acc]
  end

  def build_ecto_shorts_binding(relationship_list) do
    binding_alias = Enum.reduce(relationship_list, "ecto_shorts", fn relationship, string ->
      "#{string}_#{relationship}"
    end)
    :"#{binding_alias}"
  end
end
