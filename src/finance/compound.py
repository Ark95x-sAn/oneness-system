"""Compounding / leverage / investment banking math utilities."""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any


@dataclass
class CompoundResult:
    principal: float
    rate_annual: float
    years: float
    periods_per_year: int
    contributions: float
    final_value: float
    total_contributions: float
    total_interest: float
    schedule: list[dict[str, float]]


def compound(
    principal: float,
    rate_annual: float,
    years: float,
    periods_per_year: int = 12,
    contributions: float = 0.0,
) -> CompoundResult:
    """Compound interest with optional periodic contributions."""
    r = rate_annual / periods_per_year
    n = int(years * periods_per_year)
    schedule = []
    value = principal
    total_contrib = 0.0
    for period in range(1, n + 1):
        interest = value * r
        value += interest + contributions
        total_contrib += contributions
        if period % periods_per_year == 0 or period == n:
            schedule.append({
                "period": period,
                "value": round(value, 2),
                "contributions": round(total_contrib, 2),
                "interest_earned": round(value - principal - total_contrib, 2),
            })
    return CompoundResult(
        principal=principal,
        rate_annual=rate_annual,
        years=years,
        periods_per_year=periods_per_year,
        contributions=contributions,
        final_value=round(value, 2),
        total_contributions=round(total_contrib, 2),
        total_interest=round(value - principal - total_contrib, 2),
        schedule=schedule,
    )


def leverage_position(
    capital: float,
    leverage: float,
    entry_price: float,
    liquidation_buffer: float = 0.05,
) -> dict[str, Any]:
    """Calculate leveraged position metrics."""
    position_size = capital * leverage
    margin_required = capital
    liquidation_price = entry_price * (1 - (1 / leverage) + liquidation_buffer) if leverage > 1 else 0.0
    return {
        "capital": capital,
        "leverage": leverage,
        "position_size": round(position_size, 2),
        "margin_required": round(margin_required, 2),
        "entry_price": entry_price,
        "liquidation_price": round(liquidation_price, 4),
        "liquidation_buffer": liquidation_buffer,
    }


def kelly_criterion(probability_win: float, odds_received: float) -> float:
    """Fraction of bankroll to wager per Kelly criterion."""
    if odds_received <= 0 or probability_win <= 0 or probability_win >= 1:
        return 0.0
    return (probability_win * odds_received - (1 - probability_win)) / odds_received


def expected_value(probability_win: float, win_payout: float, loss_amount: float) -> float:
    return probability_win * win_payout - (1 - probability_win) * loss_amount
