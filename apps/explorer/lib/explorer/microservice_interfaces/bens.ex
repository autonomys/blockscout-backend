defmodule Explorer.MicroserviceInterfaces.BENS do
  @moduledoc """
    Interface to interact with Blockscout ENS microservice
  """

  alias Ecto.Association.NotLoaded
  alias Explorer.Chain

  alias Explorer.Chain.{
    Address,
    Address.CurrentTokenBalance,
    Block,
    InternalTransaction,
    Log,
    TokenTransfer,
    Transaction,
    Withdrawal
  }

  alias Explorer.Utility.Microservice
  alias HTTPoison.Response
  require Logger

  @post_timeout :timer.seconds(5)
  @request_error_msg "Error while sending request to BENS microservice"

  @typep supported_types ::
           Address.t()
           | Block.t()
           | CurrentTokenBalance.t()
           | InternalTransaction.t()
           | Log.t()
           | TokenTransfer.t()
           | Transaction.t()
           | Withdrawal.t()

  @doc """
    Batch request for ENS names via {{baseUrl}}/api/v1/:chainId/addresses:batch-resolve-names
  """
  @spec ens_names_batch_request([String.t()]) :: {:error, :disabled | String.t() | Jason.DecodeError.t()} | {:ok, any}
  def ens_names_batch_request(addresses) do
    with :ok <- Microservice.check_enabled(__MODULE__) do
      body = %{
        addresses: Enum.map(addresses, &to_string/1)
      }

      http_post_request(batch_resolve_name_url(), body)
    end
  end

  @doc """
    Request for ENS name via {{baseUrl}}/api/v1/:chainId/addresses:lookup
  """
  @spec address_lookup(binary()) :: {:error, :disabled | String.t() | Jason.DecodeError.t()} | {:ok, any}
  def address_lookup(address) do
    with :ok <- Microservice.check_enabled(__MODULE__) do
      body = %{
        "address" => to_string(address),
        "resolvedTo" => true,
        "ownedBy" => false,
        "onlyActive" => true,
        "order" => "ASC"
      }

      http_post_request(address_lookup_url(), body)
    end
  end

  @doc """
    Lookup for ENS domain name via {{baseUrl}}/api/v1/:chainId/domains:lookup
  """
  @spec ens_domain_lookup(binary()) :: {:error, :disabled | String.t() | Jason.DecodeError.t()} | {:ok, any}
  def ens_domain_lookup(domain) do
    with :ok <- Microservice.check_enabled(__MODULE__) do
      body = %{
        "name" => domain,
        "onlyActive" => true,
        "sort" => "registration_date",
        "order" => "DESC"
      }

      http_post_request(domain_lookup_url(), body)
    end
  end

  defp http_post_request(url, body) do
    headers = [{"Content-Type", "application/json"}]

    case HTTPoison.post(url, Jason.encode!(body), headers, recv_timeout: @post_timeout) do
      {:ok, %Response{body: body, status_code: 200}} ->
        Jason.decode(body)

      {_, error} ->
        old_truncate = Application.get_env(:logger, :truncate)
        Logger.configure(truncate: :infinity)

        Logger.error(fn ->
          [
            "Error while sending request to BENS microservice url: #{url}, body: #{inspect(body, limit: :infinity, printable_limit: :infinity)}: ",
            inspect(error, limit: :infinity, printable_limit: :infinity)
          ]
        end)

        Logger.configure(truncate: old_truncate)
        {:error, @request_error_msg}
    end
  end

  @spec enabled?() :: boolean
  def enabled?, do: Application.get_env(:explorer, __MODULE__)[:enabled]

  defp batch_resolve_name_url do
    "#{addresses_url()}:batch-resolve-names"
  end

  defp address_lookup_url do
    "#{addresses_url()}:lookup"
  end

  defp domain_lookup_url do
    "#{domains_url()}:lookup"
  end

  defp addresses_url do
    "#{base_url()}/addresses"
  end

  defp domains_url do
    "#{base_url()}/domains"
  end

  defp base_url do
    chain_id = Application.get_env(:block_scout_web, :chain_id)
    "#{Microservice.base_url(__MODULE__)}/api/v1/#{chain_id}"
  end

  @doc """
    Preload ENS info to list of entities if enabled?()
  """
  @spec maybe_preload_ens([supported_types] | supported_types) :: [supported_types] | supported_types
  def maybe_preload_ens(argument, function \\ &preload_ens_to_list/1) do
    if enabled?() do
      function.(argument)
    else
      argument
    end
  end

  @spec maybe_preload_ens_info_to_search_results(list()) :: list()
  def maybe_preload_ens_info_to_search_results(list) do
    maybe_preload_ens(list, &preload_ens_info_to_search_results/1)
  end

  @spec maybe_preload_ens_to_transaction(Transaction.t()) :: Transaction.t()
  def maybe_preload_ens_to_transaction(transaction) do
    maybe_preload_ens(transaction, &preload_ens_to_transaction/1)
  end

  @spec preload_ens_to_transaction(Transaction.t()) :: Transaction.t()
  def preload_ens_to_transaction(transaction) do
    [transaction_with_ens] = preload_ens_to_list([transaction])
    transaction_with_ens
  end

  @doc """
    Preload ENS names to list of entities
  """
  @spec preload_ens_to_list([supported_types]) :: [supported_types]
  def preload_ens_to_list(items) do
    address_hash_strings =
      Enum.reduce(items, [], fn item, acc ->
        acc ++ item_to_address_hash_strings(item)
      end)

    case ens_names_batch_request(address_hash_strings) do
      {:ok, result} ->
        put_ens_names(result["names"], items)

      _ ->
        items
    end
  end

  @doc """
    Preload ENS info to search result, using address_lookup/1
  """
  @spec preload_ens_info_to_search_results(list) :: list
  def preload_ens_info_to_search_results(list) do
    Enum.map(list, fn
      %{type: "address", ens_info: ens_info} = search_result when not is_nil(ens_info) ->
        search_result

      %{type: "address"} = search_result ->
        ens_info = search_result[:address_hash] |> address_lookup() |> parse_lookup_response()
        Map.put(search_result, :ens_info, ens_info)

      search_result ->
        search_result
    end)
  end

  @spec ens_domain_name_lookup(binary()) ::
          nil | %{address_hash: binary(), expiry_date: any(), name: any(), names_count: integer()}
  def ens_domain_name_lookup(domain) do
    domain |> ens_domain_lookup() |> parse_lookup_response()
  end

  defp parse_lookup_response(
         {:ok,
          %{
            "items" =>
              [
                %{"name" => name, "expiryDate" => expiry_date, "resolvedAddress" => %{"hash" => address_hash_string}}
                | _other
              ] = items
          }}
       ) do
    {:ok, hash} = Chain.string_to_address_hash(address_hash_string)

    %{
      name: name,
      expiry_date: expiry_date,
      names_count: Enum.count(items),
      address_hash: Address.checksum(hash)
    }
  end

  defp parse_lookup_response(_), do: nil

  defp item_to_address_hash_strings(%Transaction{
         to_address_hash: nil,
         created_contract_address_hash: created_contract_address_hash,
         from_address_hash: from_address_hash
       }) do
    [to_string(created_contract_address_hash), to_string(from_address_hash)]
  end

  defp item_to_address_hash_strings(%Transaction{
         to_address_hash: to_address_hash,
         created_contract_address_hash: nil,
         from_address_hash: from_address_hash
       }) do
    [to_string(to_address_hash), to_string(from_address_hash)]
  end

  defp item_to_address_hash_strings(%TokenTransfer{
         to_address_hash: to_address_hash,
         from_address_hash: from_address_hash
       }) do
    [to_string(to_address_hash), to_string(from_address_hash)]
  end

  defp item_to_address_hash_strings(%InternalTransaction{
         to_address_hash: to_address_hash,
         from_address_hash: from_address_hash
       }) do
    [to_string(to_address_hash), to_string(from_address_hash)]
  end

  defp item_to_address_hash_strings(%Log{address_hash: address_hash}) do
    [to_string(address_hash)]
  end

  defp item_to_address_hash_strings(%Withdrawal{address_hash: address_hash}) do
    [to_string(address_hash)]
  end

  defp item_to_address_hash_strings(%Block{miner_hash: miner_hash}) do
    [to_string(miner_hash)]
  end

  defp item_to_address_hash_strings(%CurrentTokenBalance{address_hash: address_hash}) do
    [to_string(address_hash)]
  end

  defp put_ens_names(names, items) do
    Enum.map(items, &put_ens_name_to_item(&1, names))
  end

  defp put_ens_name_to_item(
         %Transaction{
           to_address_hash: to_address_hash,
           created_contract_address_hash: created_contract_address_hash,
           from_address_hash: from_address_hash
         } = tx,
         names
       ) do
    %Transaction{
      tx
      | to_address: alter_address(tx.to_address, to_address_hash, names),
        created_contract_address: alter_address(tx.created_contract_address, created_contract_address_hash, names),
        from_address: alter_address(tx.from_address, from_address_hash, names)
    }
  end

  defp put_ens_name_to_item(
         %TokenTransfer{
           to_address_hash: to_address_hash,
           from_address_hash: from_address_hash
         } = tt,
         names
       ) do
    %TokenTransfer{
      tt
      | to_address: alter_address(tt.to_address, to_address_hash, names),
        from_address: alter_address(tt.from_address, from_address_hash, names)
    }
  end

  defp put_ens_name_to_item(
         %InternalTransaction{
           to_address_hash: to_address_hash,
           created_contract_address_hash: created_contract_address_hash,
           from_address_hash: from_address_hash
         } = tx,
         names
       ) do
    %InternalTransaction{
      tx
      | to_address: alter_address(tx.to_address, to_address_hash, names),
        created_contract_address: alter_address(tx.created_contract_address, created_contract_address_hash, names),
        from_address: alter_address(tx.from_address, from_address_hash, names)
    }
  end

  defp put_ens_name_to_item(%Log{address_hash: address_hash} = log, names) do
    %Log{log | address: alter_address(log.address, address_hash, names)}
  end

  defp put_ens_name_to_item(%Withdrawal{address_hash: address_hash} = withdrawal, names) do
    %Withdrawal{withdrawal | address: alter_address(withdrawal.address, address_hash, names)}
  end

  defp put_ens_name_to_item(%Block{miner_hash: miner_hash} = block, names) do
    %Block{block | miner: alter_address(block.miner, miner_hash, names)}
  end

  defp put_ens_name_to_item(%CurrentTokenBalance{address_hash: address_hash} = current_token_balance, names) do
    %CurrentTokenBalance{
      current_token_balance
      | address: alter_address(current_token_balance.address, address_hash, names)
    }
  end

  defp alter_address(_, nil, _names) do
    nil
  end

  defp alter_address(%NotLoaded{}, address_hash, names) do
    %{ens_domain_name: names[to_string(address_hash)]}
  end

  defp alter_address(%Address{} = address, address_hash, names) do
    %Address{address | ens_domain_name: names[to_string(address_hash)]}
  end
end
