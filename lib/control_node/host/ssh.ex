defmodule ControlNode.Host.SSH do
  @enforce_keys [:host, :port, :user, :private_key_dir]
  defstruct host: nil, port: 22, user: nil, private_key_dir: nil

  @type t :: %__MODULE__{host: binary, port: integer, user: binary, private_key_dir: binary}

  @doc """
  Uploads `tar_file` to the `host` server via SSH and stores it at `file_path`
  on the remote server.

  `file_path` should be absolute path on the remote server

  ## Example

  iex> ssh_config = %SSH{host: "remote-host.com", port: 22, user: "username", private_key_dir: "/home/local_user/.ssh"}
  iex> ControlNode.Host.SSH.upload_file(ssh_config, "/opt/remote/server/directory", "file_contexts_binary")
  :ok
  """
  @spec upload_file(t, binary, binary) :: :ok
  def upload_file(%__MODULE__{port: port} = ssh_config, file_path, tar_file)
      when is_integer(port) do
    with :ok <- is_absolute_path?(file_path) do
      do_upload_file(ssh_config, file_path, tar_file)

      :ok
    end
  end

  @spec connect_host(t) :: {:ok, :ssh.connection_ref()} | {:error, term()}
  defp connect_host(ssh_config) do
    ssh_options = [
      {:user, :binary.bin_to_list(ssh_config.user)},
      {:user_dir, :binary.bin_to_list(ssh_config.private_key_dir)},
      {:user_interaction, false},
      {:silently_accept_hosts, true},
      {:auth_methods, 'publickey'}
    ]

    ssh_config.host
    |> :binary.bin_to_list()
    |> :ssh.connect(ssh_config.port, ssh_options)
  end

  defp do_upload_file(ssh_config, file_path, tar_file) do
    filename = :binary.bin_to_list(file_path)
    path = Path.dirname(file_path)

    # ensure path exists
    with {:ok, conn} <- connect_host(ssh_config),
         {:ok, channel_pid} = :ssh_sftp.start_channel(conn) do
      ^path = do_make_path(channel_pid, path)
      :ssh.close(conn)
    end

    # upload file
    with {:ok, conn} <- connect_host(ssh_config),
         {:ok, channel_pid} = :ssh_sftp.start_channel(conn) do
      :ok = :ssh_sftp.write_file(channel_pid, filename, tar_file)
      :ssh.close(conn)
    end
  end

  defp is_absolute_path?(path) do
    case Path.type(path) do
      :absolute -> :ok
      _ -> {:error, :absolute_path_not_provided}
    end
  end

  defp do_make_path(channel_pid, path) do
    Path.relative_to(path, "/")
    |> Path.split()
    |> Enum.reduce("/", fn dir, base_path ->
      new_base_path = Path.join(base_path, dir)

      # ensure directory path uptil now is created
      :ssh_sftp.opendir(channel_pid, :binary.bin_to_list(new_base_path))
      |> case do
        {:ok, _} ->
          :ok

        {:error, :no_such_file} ->
          :ok = :ssh_sftp.make_dir(channel_pid, :binary.bin_to_list(new_base_path))
      end

      new_base_path
    end)
  end
end
