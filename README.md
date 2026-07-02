# nexuscore-lib

Core runtime components extracted from `nautilus_trader` for use in Walras.

## Features
- Message bus and clocks: `MessageBus`, `LiveClock`, `TestClock`, `Clock`, `TimeEvent`
- Identifiers: `TraderId`, `ComponentId`, `Identifier`, `UUID4`
- Cryptography: `hmac_signature`, `rsa_signature`, `ed25519_signature`

## Usage
```python
from nexuscore import (
    MessageBus,
    LiveClock,
    TestClock,
    Clock,
    TimeEvent,
    TraderId,
    ComponentId,
    UUID4,
    hmac_signature,
    rsa_signature,
    ed25519_signature,
)
```
