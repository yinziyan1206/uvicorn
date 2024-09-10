
from uvicorn.protocols.http.flow_control import HIGH_WATER_LIMIT


class HttpToolsProtocolWrapper:

    def on_message_begin(self) -> None:
        self.url = b""
        self.expect_100_continue = False
        self.headers = []
        self.scope = {  # type: ignore[typeddict-item]
            "type": "http",
            "asgi": {"version": self.config.asgi_version, "spec_version": "2.4"},
            "http_version": "1.1",
            "server": self.server,
            "client": self.client,
            "scheme": self.scheme,  # type: ignore[typeddict-item]
            "root_path": self.root_path,
            "headers": self.headers,
            "state": self.app_state.copy(),
        }

    def on_header(self, name: bytes, value: bytes) -> None:
        name = name.lower()
        if name == b"expect" and value.lower() == b"100-continue":
            self.expect_100_continue = True
        self.headers.append((name, value))

    def on_url(self, url: bytes) -> None:
        self.url += url

    def on_body(self, body: bytes) -> None:
        if (self.parser.should_upgrade() and self._should_upgrade()) or self.cycle.response_complete:
            return
        self.cycle.body += body
        if len(self.cycle.body) > HIGH_WATER_LIMIT:
            self.flow.pause_reading()
        self.cycle.message_event.set()

    def on_message_complete(self) -> None:
        if (self.parser.should_upgrade() and self._should_upgrade()) or self.cycle.response_complete:
            return
        self.cycle.more_body = False
        self.cycle.message_event.set()

    def on_response_complete(self) -> None:
        # Callback for pipelined HTTP requests to be started.
        self.server_state.total_requests += 1

        if self.transport.is_closing():
            return

        self._unset_keepalive_if_required()

        # Unpause data reads if needed.
        self.flow.resume_reading()

        # Unblock any pipelined events. If there are none, arm the
        # Keep-Alive timeout instead.
        if self.pipeline:
            cycle, app = self.pipeline.pop()
            task = self.loop.create_task(cycle.run_asgi(app))
            task.add_done_callback(self.tasks.discard)
            self.tasks.add(task)
        else:
            self.timeout_keep_alive_task = self.loop.call_later(
                self.timeout_keep_alive, self.timeout_keep_alive_handler
            )
