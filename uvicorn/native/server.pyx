import asyncio
import time
from email.utils import formatdate


cdef inline unsigned int calc_counter(unsigned int counter):
    return (counter + 1) % 864000


cdef inline bint check_counter(unsigned int counter):
    return counter % 10 == 0 


class ServerWrapper:

    async def main_loop(self) -> None:
        cdef unsigned int counter = 0

        should_exit = await self.on_tick(True)
        while not should_exit:
            counter = calc_counter(counter)
            await asyncio.sleep(0.1)
            should_exit = await self.on_tick(check_counter(counter))

    async def on_tick(self, change_time: bool = False) -> bool:
        if change_time:
            current_time = time.time()
            current_date = formatdate(current_time, usegmt=True).encode()

            if self.config.date_header:
                date_header = [(b"date", current_date)]
            else:
                date_header = []

            self.server_state.default_headers = date_header + self.config.encoded_headers

            # Callback to `callback_notify` once every `timeout_notify` seconds.
            if self.config.callback_notify is not None:
                if current_time - self.last_notified > self.config.timeout_notify:  # pragma: full coverage
                    self.last_notified = current_time

        # Determine if we should exit.
        if self.should_exit:
            return True
        if self.config.limit_max_requests is not None:
            return self.server_state.total_requests >= self.config.limit_max_requests
        return False
