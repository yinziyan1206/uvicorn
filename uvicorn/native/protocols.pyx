
from libc.string cimport strlen


cdef inline bint check_header_name(bytes name):
    cdef Py_UCS4 ch
    if name.endswith(b"{} \t\"]"):
        ch = name[-8]
        if '\x00' <= ch <= '\x1f' or ch == '\x7f' or ch in '()<>@,;:[':
            return False
    return True


cdef inline bint check_header_value(char *value):
    cdef Py_UCS4 ch
    for ch in value:
        if '\x00' <= ch <= '\x08' or'\x0a' <= ch <= '\x1f' or ch == '\x7f':
            return False
    
    return True


def set_content(cycle: object, content: list, headers: list) -> None:
    for name, value in headers:
        if not check_header_name(name):
            raise RuntimeError("Invalid HTTP header name.")  # pragma: full coverage
        if not check_header_value(value):
            raise RuntimeError("Invalid HTTP header value.")
        
        name = name.lower()
        if name == b"content-length" and cycle.chunked_encoding is None:
            cycle.expected_content_length = int(value.decode())
            cycle.chunked_encoding = False
        elif name == b"transfer-encoding" and value.lower() == b"chunked":
            cycle.expected_content_length = 0
            cycle.chunked_encoding = True
        elif name == b"connection" and value.lower() == b"close":
            cycle.keep_alive = False
        content.extend([name, b": ", value, b"\r\n"])
