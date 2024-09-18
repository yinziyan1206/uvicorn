import asyncio

from libc cimport time


week = ( b"Sun", b"Mon", b"Tue", b"Wed", b"Thu", b"Fri", b"Sat" )
months = ( b"Jan", b"Feb", b"Mar", b"Apr", b"May", b"Jun",
                           b"Jul", b"Aug", b"Sep", b"Oct", b"Nov", b"Dec" )


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
        cdef time.time_t current_time
        cdef time.tm *now

        if change_time:
            current_time = time.time(NULL)
            now = time.localtime(&current_time)

            current_date = b"%s, %02d %s %4d %02d:%02d:%02d GMT" % (
                week[now.tm_wday], 
                now.tm_mday, 
                months[now.tm_mon - 1], 
                now.tm_year + 1900, 
                now.tm_hour, 
                now.tm_min, 
                now.tm_sec
            )

            if self.config.date_header:
                date_header = [(b"date", current_date)]
            else:
                date_header = []

            self.server_state.default_headers = date_header + self.config.encoded_headers

            # Callback to `callback_notify` once every `timeout_notify` seconds.
            if self.config.callback_notify is not None:
                if current_time - self.last_notified > self.config.timeout_notify:  # pragma: full coverage
                    self.last_notified = current_time
                    await self.config.callback_notify()

        # Determine if we should exit.
        if self.should_exit:
            return True
        if self.config.limit_max_requests is not None:
            return self.server_state.total_requests >= self.config.limit_max_requests
        return False
