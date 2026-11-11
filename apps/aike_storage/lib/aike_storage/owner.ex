defmodule AikeStorage.Owner do
  @moduledoc """
  The service that owns a set of blobs: its Repo, its folder in the bucket and the columns
  that reference its blobs.

  Each service keeps its blobs in its own database and its own folder, so it can run on a
  separate machine with a separate database. Reference checks, purge and reconciliation
  look only at the owner's tables and only at the owner's folder: one service never deletes
  the files of another, even when they share a bucket.

  ## Fields
    - `repo`: the Ecto Repo that holds the `blobs` table
    - `folder`: the key prefix in the bucket, such as `"kyc_documents"`
    - `blob_references`: `{table, column}` pairs whose column holds a blob ID
    - `key_references`: `{table, column}` pairs whose column holds a storage key (legacy rows
      written before blobs existed)

  ## Examples

      AikeStorage.Owner.new(
        repo: DocumentOcr.Repo,
        folder: "kyc_documents",
        blob_references: [{"document_images", "blob_id"}],
        key_references: [{"document_images", "source_key"}]
      )
  """

  @enforce_keys [:repo, :folder]
  defstruct [:repo, :folder, blob_references: [], key_references: []]

  @type column_ref :: {String.t(), String.t()}
  @type t :: %__MODULE__{
          repo: module(),
          folder: String.t(),
          blob_references: [column_ref()],
          key_references: [column_ref()]
        }

  @identifier ~r/\A[a-z_][a-z0-9_]*\z/

  @doc """
  Builds an owner and checks its table and column names.

  Names go into SQL, so only lowercase identifiers are accepted.

  ## Parameters
    - fields: `:repo`, `:folder`, `:blob_references` and `:key_references`

  ## Returns
    - the owner; raises `ArgumentError` for an invalid folder, table or column name
  """
  @spec new(keyword()) :: t()
  def new(fields) do
    owner = struct!(__MODULE__, fields)

    for name <- [owner.folder | names(owner)], not Regex.match?(@identifier, name) do
      raise ArgumentError, "invalid storage owner identifier: #{inspect(name)}"
    end

    owner
  end

  defp names(owner) do
    for {table, column} <- owner.blob_references ++ owner.key_references,
        name <- [table, column],
        do: name
  end

  @doc """
  The query that tells whether a blob is referenced.

  ## Parameters
    - owner: the owner
    - id: the blob ID, dumped to binary
    - key: the blob key

  ## Returns
    - `{sql, params}`; the query selects one boolean
  """
  @spec referenced_query(t(), binary(), String.t()) :: {String.t(), [term()]}
  def referenced_query(owner, id, key) do
    conditions =
      Enum.map(owner.blob_references, &{&1, id}) ++ Enum.map(owner.key_references, &{&1, key})

    query(conditions)
  end

  @doc """
  The query that tells whether a key is referenced by a legacy key column.

  ## Parameters
    - owner: the owner
    - key: the storage key

  ## Returns
    - `{sql, params}`; the query selects one boolean
  """
  @spec key_referenced_query(t(), String.t()) :: {String.t(), [term()]}
  def key_referenced_query(owner, key),
    do: query(Enum.map(owner.key_references, &{&1, key}))

  @doc """
  The SQL condition that is true when the blob row aliased `b` is referenced.

  ## Parameters
    - owner: the owner

  ## Returns
    - a SQL boolean expression over `b.id` and `b.key`; `false` without references
  """
  @spec referenced_condition(t()) :: String.t()
  def referenced_condition(%__MODULE__{blob_references: [], key_references: []}), do: "false"

  def referenced_condition(owner) do
    blob = for {table, column} <- owner.blob_references, do: {table, column, "b.id"}
    key = for {table, column} <- owner.key_references, do: {table, column, "b.key"}

    Enum.map_join(blob ++ key, " OR ", fn {table, column, value} ->
      "EXISTS(SELECT 1 FROM #{table} WHERE #{column} = #{value})"
    end)
  end

  defp query([]), do: {"SELECT false", []}

  defp query(conditions) do
    sql =
      conditions
      |> Enum.with_index(1)
      |> Enum.map_join(" OR ", fn {{{table, column}, _value}, index} ->
        "EXISTS(SELECT 1 FROM #{table} WHERE #{column} = $#{index})"
      end)

    {"SELECT " <> sql, Enum.map(conditions, &elem(&1, 1))}
  end

  @doc """
  The foreign key constraint names that protect the owner's blobs.

  ## Parameters
    - owner: the owner

  ## Returns
    - one name per blob reference, in the Postgres default form `<table>_<column>_fkey`
  """
  @spec constraints(t()) :: [String.t()]
  def constraints(owner),
    do: for({table, column} <- owner.blob_references, do: "#{table}_#{column}_fkey")
end
