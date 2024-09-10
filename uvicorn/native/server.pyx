import asyncio
import time
from email.utils import formatdate


cdef long calc_count(long counter):
    return (counter + 1) % 864000


cdef bint tick(object server, long counter):
    if counter % 10 == 0:
        current_time = time.time()
        current_date = formatdate(current_time, usegmt=True).encode()

        if server.config.date_header:
            date_header = [(b"date", current_date)]
        else:
            date_header = []

        server.server_state.default_headers = date_header + server.config.encoded_headers

        # Callback to `callback_notify` once every `timeout_notify` seconds.
        if server.config.callback_notify is not None:
            if current_time - server.last_notified > server.config.timeout_notify:  # pragma: full coverage
                server.last_notified = current_time
                return True
    return False


class ServerWrapper:

    async def main_loop(self) -> None:
        counter = 0
        should_exit = await self.on_tick(counter)
        while not should_exit:
            counter = calc_count(counter)
            await asyncio.sleep(0.1)
            should_exit = await self.on_tick(counter)

    async def on_tick(self, counter: int) -> bool:
        # Update the default headers, once per second.
        if tick(self, counter):
            # Callback to `callback_notify` once every `timeout_notify` seconds.
            await self.config.callback_notify()

        # Determine if we should exit.
        if self.should_exit:
            return True
        if self.config.limit_max_requests is not None:
            return self.server_state.total_requests >= self.config.limit_max_requests
        return False
