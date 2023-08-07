defmodule EctoShorts.QueryBuilder.Dynamic do

  import Logger, only: [debug: 1]
  import Ecto.Query, only: [
    preload: 2, order_by: 2, dynamic: 2, join: 4, with_named_binding: 3
  ]

  alias EctoShorts.QueryBuilder

  @behaviour QueryBuilder

  @filters [
    :preload
    #:order_by
  ]

  def filters, do: @filters
  
  @impl QueryBuilder
  def create_schema_filter({:preload, val}, query) do
    query = ensure_preload_joins(query, val, [])
    val = traverse_preload(val, [])
    preload(query, ^val)
  end

  # @impl QueryBuilder
  # def create_schema_filter({:order_by, val}, query) do
  #   query = ensure_order_by_joins(query, val)
  #   val = traverse_order_by(val)
  #   order_by(query, ^val)
  # end

  defp build_ecto_shorts_binding(relationship_list) do
    binding_alias = Enum.reduce(relationship_list, "ecto_shorts", fn relationship, string ->
      "#{string}_#{relationship}"
    end)
    :"#{binding_alias}"
  end

  defp dynamic_preload(binding_alias) do
    Ecto.Query.dynamic([{^binding_alias, c}], c)
  end

  # defp dynamic_order_by(binding_alias, field) do
  #   Ecto.Query.dynamic([{^binding_alias, c}], field(c, ^field))
  # end

  defp traverse_preload(preload, relationship_list) when is_list(preload) do
    Enum.reduce(preload, [], fn p, acc ->
      resolve_preload(p, relationship_list, acc)
    end)
  end

  defp traverse_preload(preload, relationship_list) do
    traverse_preload([preload], relationship_list)
  end

  defp resolve_preload({k, {[binding_name: name], v}}, relationship_list, acc) do
    relationship_list = relationship_list ++ [k]
    [{k, {dynamic_preload(name), traverse_preload(v, relationship_list)}} | acc]
  end

  defp resolve_preload({k, {:use_join, v}}, relationship_list, acc) do
    relationship_list = relationship_list ++ [k]
    [{k, {relationship_list |> build_ecto_shorts_binding() |> dynamic_preload(), traverse_preload(v, relationship_list)}} | acc]
  end

  defp resolve_preload({k, {dynamic, v}}, relationship_list, acc) do
    relationship_list = relationship_list ++ [k]
    [{k, {dynamic, traverse_preload(v, relationship_list)}} | acc]
  end

  defp resolve_preload({k, :use_join}, relationship_list, acc) do
    relationship_list = relationship_list ++ [k]
    [{k, {relationship_list |> build_ecto_shorts_binding() |> dynamic_preload()}} | acc]
  end

  defp resolve_preload({k, [binding_name: name]}, _relationship_list, acc) do
    [{k, {dynamic_preload(name)}} | acc]
  end

  defp resolve_preload({k, v}, relationship_list, acc) when is_atom(v) or is_list(v) do
    relationship_list = relationship_list ++ [k]
    [{k, traverse_preload(v, relationship_list)} | acc]
  end

  defp resolve_preload({k, v}, _relationship_list, acc) do
    [{k, v} | acc]
  end

  defp resolve_preload(p, _relationship_list, acc) do
    [p | acc]
  end

  # defp traverse_order_by(order_by) when is_atom(order_by) do
  #   traverse_order_by([order_by])
  # end

  # defp traverse_order_by(order_by) do
  #   Enum.reduce(order_by, [], fn o, acc ->
  #     resolve_order_by(o, acc)
  #   end)
  # end

  # defp resolve_order_by(field, acc) when is_atom(field) do
  #   field
  # end

  # defp resolve_order_by({order, field}, acc) when is_atom(field) do
  #   acc ++ [{order, field}]
  # end

  # defp resolve_order_by({order, {relationship_list, field}}, acc) when is_atom(field) and is_list(relationship_list) do
  #   dynamic_binding = relationship_list
  #     |> build_ecto_shorts_binding()
  #     |> dynamic_order_by(field)
  #   acc ++ [{order, dynamic_binding}]
  # end

  def ensure_preload_joins(query, val, _relationship_list) when is_atom(val) do
    query
  end

  def ensure_preload_joins(query, val, relationship_list) do
    Enum.reduce(val, query, fn p, acc ->
      resolve_preload_joins(p, relationship_list, acc)
    end)
  end

  defp resolve_preload_joins({k, {:use_join, v}}, relationship_list, acc) do
    relationship_list = relationship_list ++ [k]
    acc
    |> ensure_ecto_shorts_binding_in_query(relationship_list)
    |> ensure_preload_joins(v, relationship_list)
  end

  defp resolve_preload_joins({k, {_dynamic, v}}, relationship_list, acc) do
    relationship_list = relationship_list ++ [k]
    ensure_preload_joins(acc, v, relationship_list)
  end

  defp resolve_preload_joins({k, :use_join}, relationship_list, acc) do
    relationship_list = relationship_list ++ [k]
    acc
    |> ensure_ecto_shorts_binding_in_query(relationship_list)
  end

  defp resolve_preload_joins({_k, [binding_name: _name]}, _relationship_list, acc) do
    acc
  end

  defp resolve_preload_joins({k, v}, relationship_list, acc) when is_atom(v) or is_list(v) do
    relationship_list = relationship_list ++ [k]
    ensure_preload_joins(acc, v, relationship_list)
  end

  defp resolve_preload_joins({_, _}, _relationship_list, acc) do
    acc
  end

  defp resolve_preload_joins(_p, _relationship_list, acc) do
    acc
  end

  def ensure_ecto_shorts_binding_in_query(query, []) do
    query
  end

  def ensure_ecto_shorts_binding_in_query(query, relationship_list) do
    {new_query, _} = Enum.reduce(relationship_list, {query, :ecto_shorts}, fn relationship, {query, previous_binding} ->
      new_binding = "#{previous_binding}_#{relationship}"
      new_query = put_named_binding_in_query(query, previous_binding, relationship)
      {new_query, :"#{new_binding}"}
    end)
    new_query
  end

  defp put_named_binding_in_query(query, :ecto_shorts, next_field) do
    Ecto.Query.with_named_binding(query, :"ecto_shorts_#{next_field}", fn query, binding_alias ->
      Ecto.Query.join(
        query,
        :inner,
        [scm],
        assoc in assoc(scm, ^next_field), as: ^binding_alias
      )
    end)
  end

  defp put_named_binding_in_query(query, previous_binding, next_field) do
    Ecto.Query.with_named_binding(query, :"#{previous_binding}_#{next_field}", fn query, binding_alias ->
      Ecto.Query.join(
        query,
        :inner,
        [{^previous_binding, scm}],
        assoc in assoc(scm, ^next_field), as: ^binding_alias
      )
    end)
  end
end