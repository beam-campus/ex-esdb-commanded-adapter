defmodule ExESDB.Commanded.Config do
  @moduledoc """
  Simple configuration for ExESDB.Commanded.Adapter.
  
  Expects configuration in the standard Commanded format:
  
      config :my_otp_app, MyApp.CommandedApp,
        event_store: [
          event_type_mapper: MyApp.EventTypeMapper,
          store_id: :my_store,
          log_level: :info,
          adapter: ExESDB.Commanded.Adapter,
          stream_prefix: "my_app_"
        ]
  """
  
  require Logger
  
  @type config :: Keyword.t()
  
  @doc """
  Gets event store configuration from the application config.
  
  The otp_app and commanded_app are passed from the adapter's child_spec.
  """
  @spec event_store_config(atom(), atom()) :: Keyword.t()
  def event_store_config(otp_app, commanded_app) do
    app_config = Application.get_env(otp_app, commanded_app, [])
    event_store_config = Keyword.get(app_config, :event_store, [])
    
    # Validate configuration exists
    case {app_config, event_store_config} do
      {[], []} ->
        Logger.error("""
        ========================== CRITICAL ERROR ==========================
        NO CONFIGURATION FOUND FOR ExESDB.Commanded.Adapter!
        
        Missing configuration for: #{otp_app} -> #{commanded_app}
        
        You MUST add configuration like this to your config files:
        
        config :#{otp_app}, #{commanded_app},
          event_store: [
            adapter: ExESDB.Commanded.Adapter,
            event_type_mapper: #{otp_app |> to_string() |> Macro.camelize()}.EventTypeMapper,
            store_id: :my_store,
            stream_prefix: "my_prefix_",
            log_level: :info
          ]
        ==================================================================
        """)
        []
        
      {_app_config, []} ->
        Logger.error("""
        ========================== CRITICAL ERROR ==========================
        NO EVENT_STORE CONFIGURATION FOUND!
        
        Found app config for #{otp_app} -> #{commanded_app} but missing :event_store key
        
        Add event_store configuration:
        
        config :#{otp_app}, #{commanded_app},
          event_store: [
            adapter: ExESDB.Commanded.Adapter,
            event_type_mapper: #{otp_app |> to_string() |> Macro.camelize()}.EventTypeMapper,
            store_id: :my_store
          ]
        ==================================================================
        """)
        []
        
      {_app_config, config} when is_list(config) ->
        Logger.info("Found event_store configuration for #{otp_app} -> #{commanded_app}")
        validate_event_store_config(config, otp_app, commanded_app)
        
      {_app_config, invalid} ->
        Logger.error("""
        ========================== CRITICAL ERROR ==========================
        INVALID EVENT_STORE CONFIGURATION!
        
        Expected a keyword list but got: #{inspect(invalid)}
        
        Configuration must be a keyword list like:
        
        config :#{otp_app}, #{commanded_app},
          event_store: [
            adapter: ExESDB.Commanded.Adapter,
            event_type_mapper: MyApp.EventTypeMapper
          ]
        ==================================================================
        """)
        []
    end
  end
  
  @doc """
  Validates the event store configuration and warns about missing critical components.
  """
  @spec validate_event_store_config(Keyword.t(), atom(), atom()) :: Keyword.t()
  def validate_event_store_config(config, otp_app, commanded_app) do
    # Check for adapter
    case Keyword.get(config, :adapter) do
      ExESDB.Commanded.Adapter ->
        Logger.debug("Correct adapter configured: ExESDB.Commanded.Adapter")
        
      nil ->
        Logger.warning("""
        ========================== WARNING ==========================
        NO ADAPTER SPECIFIED IN EVENT_STORE CONFIG!
        
        Add adapter to your configuration:
        adapter: ExESDB.Commanded.Adapter
        ==========================================================
        """)
        
      other ->
        Logger.warning("""
        ========================== WARNING ==========================
        DIFFERENT ADAPTER CONFIGURED: #{inspect(other)}
        
        This configuration is for ExESDB.Commanded.Adapter
        If you're using a different adapter, this config may not apply.
        ==========================================================
        """)
    end
    
    # Check for event_type_mapper
    case Keyword.get(config, :event_type_mapper) do
      nil ->
        Logger.error("""
        ========================== CRITICAL ERROR ==========================
        NO EVENT_TYPE_MAPPER CONFIGURED!
        
        This is REQUIRED for proper event handling!
        
        Add to your configuration:
        event_type_mapper: #{otp_app |> to_string() |> Macro.camelize()}.EventTypeMapper
        
        And create the mapper module:
        
        defmodule #{otp_app |> to_string() |> Macro.camelize()}.EventTypeMapper do
          def to_event_type(module_name) when is_atom(module_name) do
            module_name |> to_string() |> String.replace("Elixir.", "")
          end
        end
        ==================================================================
        """)
        
      mapper when is_atom(mapper) ->
        validate_event_type_mapper(mapper)
        
      invalid ->
        Logger.error("""
        ========================== CRITICAL ERROR ==========================
        INVALID EVENT_TYPE_MAPPER: #{inspect(invalid)}
        
        event_type_mapper must be a module atom, got: #{inspect(invalid)}
        ==================================================================
        """)
    end
    
    # Check for store_id
    case Keyword.get(config, :store_id) do
      nil ->
        Logger.warning("""
        ========================== WARNING ==========================
        NO STORE_ID CONFIGURED - using default :ex_esdb
        
        Consider adding: store_id: :my_store_name
        ==========================================================
        """)
        
      store_id when is_atom(store_id) ->
        Logger.info("Store ID configured: #{store_id}")
        
      invalid ->
        Logger.error("""
        ========================== ERROR ==========================
        INVALID STORE_ID: #{inspect(invalid)}
        
        store_id must be an atom, got: #{inspect(invalid)}
        ========================================================
        """)
    end
    
    config
  end
  
  @doc """
  Validates that the event type mapper module exists and has required functions.
  """
  @spec validate_event_type_mapper(module()) :: :ok
  def validate_event_type_mapper(mapper) when is_atom(mapper) do
    try do
      Code.ensure_loaded!(mapper)
      
      if function_exported?(mapper, :to_event_type, 1) do
        Logger.info("Event type mapper validated: #{inspect(mapper)}")
        :ok
      else
        Logger.error("""
        ========================== CRITICAL ERROR ==========================
        EVENT_TYPE_MAPPER MISSING REQUIRED FUNCTION!
        
        Module #{inspect(mapper)} exists but doesn't export to_event_type/1
        
        Add this function to your mapper:
        
        def to_event_type(module_name) when is_atom(module_name) do
          module_name |> to_string() |> String.replace("Elixir.", "")
        end
        ==================================================================
        """)
        :error
      end
    rescue
      error ->
        Logger.error("""
        ========================== CRITICAL ERROR ==========================
        EVENT_TYPE_MAPPER MODULE NOT FOUND!
        
        Module #{inspect(mapper)} could not be loaded: #{inspect(error)}
        
        Create the module or fix the module name in your configuration.
        ==================================================================
        """)
        :error
    end
  end
  
  @doc """
  Gets a specific configuration value with a default.
  """
  @spec get_config(atom(), atom(), atom(), any()) :: any()
  def get_config(otp_app, commanded_app, key, default \\ nil) do
    event_store_config(otp_app, commanded_app)
    |> Keyword.get(key, default)
  end
  
  @doc """
  Gets the store ID from configuration.
  """
  @spec store_id(atom(), atom()) :: atom()
  def store_id(otp_app, commanded_app) do
    get_config(otp_app, commanded_app, :store_id, :ex_esdb)
  end
  
  @doc """
  Gets the stream prefix from configuration.
  """
  @spec stream_prefix(atom(), atom()) :: String.t()
  def stream_prefix(otp_app, commanded_app) do
    get_config(otp_app, commanded_app, :stream_prefix, "")
  end
  
  @doc """
  Gets the serializer module from configuration.
  """
  @spec serializer(atom(), atom()) :: module()
  def serializer(otp_app, commanded_app) do
    get_config(otp_app, commanded_app, :serializer, Jason)
  end
  
  @doc """
  Gets the event type mapper from configuration.
  """
  @spec event_type_mapper(atom(), atom()) :: module() | nil
  def event_type_mapper(otp_app, commanded_app) do
    get_config(otp_app, commanded_app, :event_type_mapper)
  end
  
  @doc """
  Gets the log level from configuration.
  """
  @spec log_level(atom(), atom()) :: atom()
  def log_level(otp_app, commanded_app) do
    get_config(otp_app, commanded_app, :log_level, :info)
  end
end
