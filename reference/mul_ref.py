"""Golden model for the unsigned W x W -> 2W multipliers in parametrized_primitives/."""


def mul_ref(a: int, b: int, w: int) -> int:
    """Returns the exact 2w-bit product of two w-bit unsigned operands."""
    mask = (1 << w) - 1
    if not (0 <= a <= mask and 0 <= b <= mask):
        raise ValueError(f"operands must be {w}-bit unsigned: a={a:#x} b={b:#x}")
    return a * b
