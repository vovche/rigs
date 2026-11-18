/* qemu_monitor.vala — QEMU human monitor (HMP) over a Unix socket, without a shell.
 * Never build HMP or shell command lines by concatenating paths: use quote(). */
namespace Rigs {
    public class HmpMonitor : Object {
        // HMP string argument: double quotes with \\ and \" escapes. Control characters
        // (newline would start a second monitor command) are rejected outright.
        public static string quote(string value) throws Error {
            if (!value.validate()) throw new IOError.INVALID_ARGUMENT("Monitor argument is not valid UTF-8.");
            var out_s = new StringBuilder("\"");
            for (int i = 0; i < value.length; i++) {
                char c = value[i];
                if ((uchar) c < 0x20 || c == 0x7f)
                    throw new IOError.INVALID_ARGUMENT("Monitor argument contains control characters.");
                if (c == '\\' || c == '"') out_s.append_c('\\');
                out_s.append_c(c);
            }
            out_s.append_c('"');
            return out_s.str;
        }

        public static void validate_command(string command) throws Error {
            if (command.length == 0 || command.index_of_char('\n') >= 0 || command.index_of_char('\r') >= 0)
                throw new IOError.INVALID_ARGUMENT("A monitor command must be a single line.");
        }

        // Sends one command and waits (bounded) for the next prompt so QEMU processes it before we close.
        public static string send(string socket_path, string command, uint timeout_s = 2) throws Error {
            validate_command(command);
            var client = new SocketClient();
            client.timeout = timeout_s;
            var connection = client.connect(new UnixSocketAddress(socket_path));
            connection.socket.timeout = timeout_s;
            var reply = new StringBuilder();
            try {
                size_t written;
                connection.output_stream.write_all((command + "\n").data, out written);
                int64 deadline = get_monotonic_time() + (int64) timeout_s * 1000000;
                uint8[] buffer = new uint8[4096];
                // Banner + first prompt, then the command echo/output + second prompt.
                while (get_monotonic_time() < deadline && count_prompts(reply.str) < 2 && reply.len < 65536) {
                    ssize_t n = connection.input_stream.read(buffer);
                    if (n <= 0) break;
                    reply.append(HostCommand.bytes_to_text(new Bytes(buffer[0:(int) n])));
                }
            } catch (IOError.TIMED_OUT e) {
                // The command was written; a silent monitor is not a failure.
            } finally {
                try { connection.close(); } catch (Error e) { }
            }
            return reply.str;
        }

        private static int count_prompts(string text) {
            int count = 0, index = 0;
            while ((index = text.index_of("(qemu)", index)) >= 0) { count++; index += 6; }
            return count;
        }
    }
}
