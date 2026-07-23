import pytest

from nexuscore import LiveClock
from nexuscore import TraderId


@pytest.fixture
def clock():
    return LiveClock()


@pytest.fixture
def trader_id():
    return TraderId("TRADER-001")
