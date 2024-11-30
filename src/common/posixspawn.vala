
public class ProcessLauncher : Object {
	public signal void complete();
	private int spipe;
	private int epipe;
	private Pid child_pid;
	public int get_stdout_pipe() {
		return spipe;
	}
	public int get_stderr_pipe() {
		return epipe;
	}

	public IOChannel get_stdout_iochan() {
		return new IOChannel.unix_new(spipe);
	}

	public IOChannel get_stderr_iochan() {
		return new IOChannel.unix_new(epipe);
	}

	public bool run_command(string cmd, int flags) {
		string []exa;
		try {
			Shell.parse_argv(cmd, out exa);
			return run_argv(exa, flags);
		} catch {}
		return false;
	}

	public bool run_argv(string[]? argv, int flags) {
		spipe = -1;
		epipe = -1;
		SpawnFlags spfl = SpawnFlags.SEARCH_PATH | SpawnFlags.DO_NOT_REAP_CHILD;
		if ((flags & 1) == 0) {
			spfl |= SpawnFlags.STDOUT_TO_DEV_NULL;
		}
		if ((flags & 2) == 0) {
			spfl |= SpawnFlags.STDERR_TO_DEV_NULL;
		}
		try {
			Process.spawn_async_with_pipes (null,
											argv,
											null,
											spfl,
											null,
											out child_pid,
											null,
											out spipe,
											out epipe);
			ChildWatch.add (child_pid, (pid, status) => {
					Process.close_pid (pid);
					complete();
				});
			return true;
		} catch (Error e) {
			print("%s\n", e.message);
			return false;
		}
	}

	public int get_pid() {
		return child_pid;
	}

	public static void kill(int pid) {
		Posix.kill(pid, ProcessSignal.TERM);
	}

	public static void suspend(int pid) {
		Posix.kill(pid, ProcessSignal.STOP);
	}

	public static void resume(int pid) {
		Posix.kill(pid, ProcessSignal.CONT);
	}
}
