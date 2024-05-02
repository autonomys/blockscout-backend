<<<<<<<< HEAD:apps/explorer/lib/explorer/chain/import/runner/polygon_zkevm/batch_transactions.ex
defmodule Explorer.Chain.Import.Runner.PolygonZkevm.BatchTransactions do
  @moduledoc """
  Bulk imports `t:Explorer.Chain.PolygonZkevm.BatchTransaction.t/0`.
========
defmodule Explorer.Chain.Import.Runner.ZkSync.BatchTransactions do
  @moduledoc """
  Bulk imports `t:Explorer.Chain.ZkSync.BatchTransaction.t/0`.
>>>>>>>> master:apps/explorer/lib/explorer/chain/import/runner/zksync/batch_transactions.ex
  """

  require Ecto.Query

  alias Ecto.{Changeset, Multi, Repo}
  alias Explorer.Chain.Import
<<<<<<<< HEAD:apps/explorer/lib/explorer/chain/import/runner/polygon_zkevm/batch_transactions.ex
  alias Explorer.Chain.PolygonZkevm.BatchTransaction
========
  alias Explorer.Chain.ZkSync.BatchTransaction
>>>>>>>> master:apps/explorer/lib/explorer/chain/import/runner/zksync/batch_transactions.ex
  alias Explorer.Prometheus.Instrumenter

  @behaviour Import.Runner

  # milliseconds
  @timeout 60_000

  @type imported :: [BatchTransaction.t()]

  @impl Import.Runner
  def ecto_schema_module, do: BatchTransaction

  @impl Import.Runner
<<<<<<<< HEAD:apps/explorer/lib/explorer/chain/import/runner/polygon_zkevm/batch_transactions.ex
  def option_key, do: :polygon_zkevm_batch_transactions
========
  def option_key, do: :zksync_batch_transactions
>>>>>>>> master:apps/explorer/lib/explorer/chain/import/runner/zksync/batch_transactions.ex

  @impl Import.Runner
  @spec imported_table_row() :: %{:value_description => binary(), :value_type => binary()}
  def imported_table_row do
    %{
      value_type: "[#{ecto_schema_module()}.t()]",
      value_description: "List of `t:#{ecto_schema_module()}.t/0`s"
    }
  end

  @impl Import.Runner
  @spec run(Multi.t(), list(), map()) :: Multi.t()
  def run(multi, changes_list, %{timestamps: timestamps} = options) do
    insert_options =
      options
      |> Map.get(option_key(), %{})
      |> Map.take(~w(on_conflict timeout)a)
      |> Map.put_new(:timeout, @timeout)
      |> Map.put(:timestamps, timestamps)

<<<<<<<< HEAD:apps/explorer/lib/explorer/chain/import/runner/polygon_zkevm/batch_transactions.ex
    Multi.run(multi, :insert_polygon_zkevm_batch_transactions, fn repo, _ ->
      Instrumenter.block_import_stage_runner(
        fn -> insert(repo, changes_list, insert_options) end,
        :block_referencing,
        :polygon_zkevm_batch_transactions,
        :polygon_zkevm_batch_transactions
========
    Multi.run(multi, :insert_zksync_batch_transactions, fn repo, _ ->
      Instrumenter.block_import_stage_runner(
        fn -> insert(repo, changes_list, insert_options) end,
        :block_referencing,
        :zksync_batch_transactions,
        :zksync_batch_transactions
>>>>>>>> master:apps/explorer/lib/explorer/chain/import/runner/zksync/batch_transactions.ex
      )
    end)
  end

  @impl Import.Runner
  def timeout, do: @timeout

  @spec insert(Repo.t(), [map()], %{required(:timeout) => timeout(), required(:timestamps) => Import.timestamps()}) ::
          {:ok, [BatchTransaction.t()]}
          | {:error, [Changeset.t()]}
  def insert(repo, changes_list, %{timeout: timeout, timestamps: timestamps} = _options) when is_list(changes_list) do
<<<<<<<< HEAD:apps/explorer/lib/explorer/chain/import/runner/polygon_zkevm/batch_transactions.ex
    # Enforce PolygonZkevm.BatchTransaction ShareLocks order (see docs: sharelock.md)
========
    # Enforce ZkSync.BatchTransaction ShareLocks order (see docs: sharelock.md)
>>>>>>>> master:apps/explorer/lib/explorer/chain/import/runner/zksync/batch_transactions.ex
    ordered_changes_list = Enum.sort_by(changes_list, & &1.hash)

    {:ok, inserted} =
      Import.insert_changes_list(
        repo,
        ordered_changes_list,
        for: BatchTransaction,
        returning: true,
        timeout: timeout,
        timestamps: timestamps,
        conflict_target: :hash,
        on_conflict: :nothing
      )

    {:ok, inserted}
  end
end
