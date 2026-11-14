"""Check the effective Asphalt UFS clock/power contract in the compiled DTB."""
import subprocess
import sys


def get(node, prop, kind="x"):
    return subprocess.check_output(
        ["fdtget", "-t", kind, sys.argv[1], node, prop], text=True
    ).split()


def cells(node, prop):
    return [int(value, 16) for value in get(node, prop)]


ufs = "/soc@0/ufshc@1d84000"
ice = "/soc@0/crypto@1d88000"
gcc = "/soc@0/clock-controller@100000"
rpmh = "/soc@0/rsc@17a00000/power-controller"
assert get(ufs, "compatible", "s")[0] == "qcom,sm8475-ufshc"
assert get(ufs, "clock-names", "s") == [
    "core_clk", "bus_aggr_clk", "iface_clk", "core_clk_unipro", "ref_clk",
    "tx_lane0_sync_clk", "rx_lane0_sync_clk", "rx_lane1_sync_clk", "ice_core_clk",
]
assert len(cells(ufs, "clocks")) == 18
assert "required-opps" not in subprocess.check_output(
    ["fdtget", "-p", sys.argv[1], ufs], text=True
).split()
assert cells(ufs, "clocks")[-2:] == cells(ice, "assigned-clocks")
assert cells(ice, "assigned-clock-rates") == [75_000_000]
# The two parents must be distinct RPMh CX/MX domains (RPMHPD_CX=0, MX=8).
parents = cells(gcc, "power-domains")
assert parents == [cells(rpmh, "phandle")[0], 0, cells(rpmh, "phandle")[0], 8]
for freq, level, name in ((75_000_000, 64, "opp4"), (850_000_000, 416, "opp14")):
    opp = ufs + "/opp-table/opp-" + str(freq)
    values = cells(opp, "opp-hz")
    assert len(values) == 18 and all(values[i] == 0 for i in range(0, 18, 2))
    assert values[1::2] == [freq, 0, 0, freq, 0, 0, 0, 0, freq]
    target = cells(opp, "required-opps")
    if freq == 75_000_000:
        assert target == cells(ice, "required-opps")
    # Resolve the actual RPMh OPP by its performance level and phandle.
    power_opp = rpmh + "/opp-table/" + name
    assert cells(power_opp, "opp-level") == [level]
    assert cells(power_opp, "phandle") == target
print("Asphalt UFS: turbo compatible, nine clocks, coordinated OPPs and CX/MX parents passed")
