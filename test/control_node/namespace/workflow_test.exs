defmodule ControlNode.Namespace.WorkflowTest do
  use ExUnit.Case
  import Mock
  import ControlNode.Factory
  import ControlNode.TestUtils
  alias ControlNode.{Release, Namespace}

  defmodule ServiceApp do
    use ControlNode.Release,
      spec: %ControlNode.Release.Spec{name: :service_app, base_path: "/app/service_app"}
  end

  describe "ServiceApp.start_link/1" do
    setup_with_mocks([
      {Release, [],
       [
         initialize_state: &mock_initialize_state/3,
         terminate_state: &mock_terminate_state/2,
         deploy: &mock_deploy/4
       ]}
    ]) do
      :ok
    end

    test "transitions to [state: :manage] when release is not running" do
      namespace_spec = build(:namespace_spec, hosts: [build(:host_spec)])
      {:ok, _pid} = ServiceApp.start_link(namespace_spec)

      assert_until(fn -> {:manage, _} = :sys.get_state(:service_app_testing) end)
    end

    test "transitions to [state: :observe] when CONTROL_MODE is OBSERVE" do
      System.put_env("CONTROL_MODE", "OBSERVE")

      namespace_spec = build(:namespace_spec, hosts: [build(:host_spec)])
      {:ok, _pid} = ServiceApp.start_link(namespace_spec)

      assert_until(fn -> {:observe, _} = :sys.get_state(:service_app_testing) end)

      System.put_env("CONTROL_MODE", "MANAGE")
    end

    @tag capture_log: true
    test "deploys release version; stopping after 5 failed attempts" do
      hosts = [build(:host_spec), build(:host_spec, host: "localhost2")]
      namespace_spec = build(:namespace_spec, hosts: hosts)

      {:ok, _pid} = ServiceApp.start_link(namespace_spec)

      assert_until(fn ->
        {:failed_deployment, %{deploy_attempts: 5}} = :sys.get_state(:service_app_testing)
      end)
    end
  end

  describe "ServiceApp.init/1" do
    setup do
      System.put_env("CONTROL_MODE", "OBSERVE")
      on_exit(fn -> System.put_env("CONTROL_MODE", "MANAGE") end)
    end

    test "transitions to [state: :initialize] and event :observe_namespace_state" do
      namespace_spec = build(:namespace_spec, hosts: [build(:host_spec)])

      actions = [
        {:change_callback_module, ControlNode.Namespace.Initialize},
        {:next_event, :internal, :observe_namespace_state}
      ]

      assert {:ok, :initialize, _, next_actions} = ServiceApp.init(namespace_spec)
      assert next_actions == actions
    end
  end

  defp mock_initialize_state(_release_spec, %{host: "localhost2"} = host_spec, _cookie) do
    build(:release_state, host: host_spec)
  end

  defp mock_initialize_state(_release_spec, host_spec, _cookie) do
    %Release.State{host: host_spec, status: :not_running}
  end

  defp mock_deploy(_release_spec, _release_state, _registry_spec, _version) do
    throw("Some exception")
  end

  defp mock_terminate_state(_, _), do: :ok
end
