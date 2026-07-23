# nexuscore-lib

Core runtime components extracted from `nautilus_trader` for use in Walras.
Pure Cython + Python standard library — no Rust or other native dependencies.

## Features
- Message bus and clock: `MessageBus`, `LiveClock`, `Clock`, `TimeEvent`
- Identifiers: `TraderId`, `ComponentId`, `Identifier`, `UUID4`
- Cryptography: `hmac_signature` (HMAC-SHA256), `HmacSigner`

## Usage
```python
from nexuscore import (
    MessageBus,
    LiveClock,
    Clock,
    TimeEvent,
    TraderId,
    ComponentId,
    UUID4,
    hmac_signature,
    HmacSigner,
)
```
