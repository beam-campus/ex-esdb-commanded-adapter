defmodule ConfigVerificationTest do
  use ExUnit.Case
  import ExUnit.CaptureLog
  
  alias ExESDB.Commanded.Adapter

  # Mock event type mappers for testing
  defmodule TestDirectApp.EventTypeMapper do
    def to_string(event_type) when is_atom(event_type) do
      event_type |> Atom.to_string() |> String.replace("Elixir.", "")
    end
    def to_string(event_type) when is_binary(event_type), do: event_type
    def to_atom(event_type) when is_binary(event_type), do: String.to_atom(event_type)
    def to_atom(event_type) when is_atom(event_type), do: event_type
  end

  # Mock event type mapper modules for known apps
  defmodule ReckonAccounts.EventTypeMapper do
    def to_string(event_type) when is_atom(event_type), do: Atom.to_string(event_type)
    def to_atom(event_type) when is_binary(event_type), do: String.to_atom(event_type)
  end

  describe "umbrella app configuration" do
    setup do
      # Clean up any existing event_type_mapper in process dictionary
      Process.delete(:event_type_mapper)
      
      on_exit(fn ->
        # Clean up after tests
        Process.delete(:event_type_mapper)
        cleanup_test_configurations()
      end)
      
      :ok
    end

    test "child_spec creates adapter_meta with correct application reference" do
      # Test that child_spec correctly stores the application reference
      opts = [
        store_id: :test_umbrella,
        stream_prefix: "test_umbrella_",
        serializer: Jason
      ]
      
      {:ok, _child_specs, adapter_meta} = Adapter.child_spec(:test_umbrella_app, opts)
      
      assert adapter_meta.application == :test_umbrella_app
      assert adapter_meta.store_id == :test_umbrella
      assert adapter_meta.stream_prefix == "test_umbrella_"
      assert adapter_meta.serializer == Jason
    end

    test "umbrella app configuration works for reckon_accounts" do
      # Test with a real known app - reckon_accounts
      # Set up configuration like in an umbrella app where config is under CommandedApp module
      Application.put_env(:reckon_accounts, ReckonAccounts.CommandedApp, [
        event_store: [
          adapter: ExESDB.Commanded.Adapter,
          store_id: :reckon_accounts,
          stream_prefix: "reckon_accounts_",
          serializer: Jason,
          event_type_mapper: ReckonAccounts.EventTypeMapper
        ]
      ])
      
      adapter_meta = %{
        store_id: :reckon_accounts,
        stream_prefix: "reckon_accounts_",
        serializer: Jason,
        application: :reckon_accounts
      }

      # Test that configuration is found and no warnings are produced
      log = capture_log(fn ->
        try do
          # Create a minimal event to test configuration loading
          event_data = %Commanded.EventStore.EventData{
            causation_id: "test-causation",
            correlation_id: "test-correlation", 
            event_type: "TestEvent",
            data: %{test: "data"},
            metadata: %{}
          }
          
          # This call will internally call set_event_type_mapper
          # We expect it to fail on the actual ExESDB call, but config should be loaded first
          Adapter.append_to_stream(adapter_meta, "test-stream", 0, [event_data], [])
        rescue
          # We expect this to fail because we're not running a real ExESDB instance
          # but the configuration loading should happen before the failure
          _ -> :ok
        end
      end)

      # The key test: should not contain the warning about config not being a list
      refute log =~ "ADAPTER: event_store config is not a list"
      # Should contain confirmation that mapper was found and set
      assert log =~ "ADAPTER: Setting event_type_mapper to"
    end

    test "configuration lookup falls back to direct app config" do
      # Set up configuration directly under the app (non-umbrella style)
      Application.put_env(:test_direct_app, :event_store, [
        adapter: ExESDB.Commanded.Adapter,
        store_id: :test_direct,
        stream_prefix: "test_direct_",
        serializer: Jason,
        event_type_mapper: TestDirectApp.EventTypeMapper
      ])
      
      adapter_meta = %{
        store_id: :test_direct,
        stream_prefix: "test_direct_",
        serializer: Jason,
        application: :test_direct_app
      }

      # Test that direct configuration is found
      log = capture_log(fn ->
        try do
          event_data = %Commanded.EventStore.EventData{
            causation_id: "test-causation",
            correlation_id: "test-correlation", 
            event_type: "TestEvent",
            data: %{test: "data"},
            metadata: %{}
          }
          
          Adapter.append_to_stream(adapter_meta, "test-stream", 0, [event_data], [])
        rescue
          _ -> :ok
        end
      end)

      # Should find the direct configuration without warnings
      refute log =~ "ADAPTER: event_store config is not a list"
      refute log =~ "ADAPTER: No event type mapper found in process dictionary!"
    end

    test "known app mappings are correct" do
      # Test the hardcoded app mappings work as expected
      # This is a bit of a white-box test, but important for umbrella app support
      
      # We'll test this by setting up configurations for known apps
      known_apps = [
        {:reckon_accounts, ReckonAccounts.CommandedApp},
        {:reckon_memberships, ReckonMemberships.CommandedApp},
        {:reckon_payments, ReckonPayments.CommandedApp},
        {:reckon_profiles, ReckonProfiles.CommandedApp},
        {:greenhouse_tycoon, GreenhouseTycoon.CommandedApp},
        {:landing_site, LandingSite.CommandedApp}
      ]
      
      for {app_name, commanded_app_module} <- known_apps do
        # Set up umbrella-style configuration
        Application.put_env(app_name, commanded_app_module, [
          event_store: [
            adapter: ExESDB.Commanded.Adapter,
            store_id: app_name,
            event_type_mapper: String.to_atom("#{commanded_app_module}.EventTypeMapper")
          ]
        ])
        
        adapter_meta = %{
          store_id: app_name,
          stream_prefix: "#{app_name}_",
          application: app_name
        }

        # Test that configuration lookup works without warnings
        log = capture_log(fn ->
          try do
            event_data = %Commanded.EventStore.EventData{
              causation_id: "test",
              correlation_id: "test", 
              event_type: "Test",
              data: %{},
              metadata: %{}
            }
            Adapter.append_to_stream(adapter_meta, "test", 0, [event_data], [])
          rescue
            _ -> :ok
          end
        end)

        refute log =~ "ADAPTER: event_store config is not a list", 
               "Failed for app: #{app_name}"
      end
    end
  end

  # Helper to add test app mappings (simulates extending the hardcoded list)
  defp add_test_app_mapping(app_name, commanded_app_module) do
    # In a real implementation, this would extend get_commanded_app_module/1
    # For testing, we'll set up the configuration in the expected location
    :ok
  end

  defp cleanup_test_configurations do
    apps_to_clean = [
      :test_umbrella_app,
      :test_direct_app,
      :reckon_accounts,
      :reckon_memberships, 
      :reckon_payments,
      :reckon_profiles,
      :greenhouse_tycoon,
      :landing_site
    ]
    
    for app <- apps_to_clean do
      Application.delete_env(app, :event_store)
      
      # Also clean up any CommandedApp configs
      modules_to_try = [
        ReckonAccounts.CommandedApp,
        ReckonMemberships.CommandedApp,
        ReckonPayments.CommandedApp, 
        ReckonProfiles.CommandedApp,
        GreenhouseTycoon.CommandedApp,
        LandingSite.CommandedApp,
        TestUmbrellaApp.CommandedApp
      ]
      
      for module <- modules_to_try do
        try do
          Application.delete_env(app, module)
        rescue
          _ -> :ok
        end
      end
    end
  end
end

