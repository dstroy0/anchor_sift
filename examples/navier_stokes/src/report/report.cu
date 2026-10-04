// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// report.cu: writing exact values (report.h)
#include "report.h"

void report_value(ScripturaLine *line, SimRational value, unsigned int places)
{
    if (sim_rational_sign(value) == 0)
    {
        scriptura_character(line, '0');
        return;
    }
    if (sim_rational_sign(value) < 0)
    {
        scriptura_character(line, '-');
        value = sim_rational_absolute(value);
    }
    const SimRational ten = sim_rational(10ll, 1ll);
    const SimRational one = sim_rational(1ll, 1ll);
    long long exponent = 0ll;
    while (sim_rational_sign(sim_rational_difference(value, ten)) >= 0)
    {
        value = sim_rational_product(value, sim_rational_reciprocal(ten));
        exponent += 1ll;
    }
    while (sim_rational_sign(sim_rational_difference(value, one)) < 0)
    {
        value = sim_rational_product(value, ten);
        exponent -= 1ll;
    }
    sim_ratio_print(line, &value.numerator, &value.denominator, places);
    if (exponent != 0ll)
    {
        scriptura_character(line, 'e');
        scriptura_signed(line, exponent);
    }
}

void report_line(ScripturaLine *line, const char *name, SimRational value, const char *unit, unsigned int places)
{
    scriptura_text(line, "  ");
    scriptura_text(line, name);
    scriptura_text(line, " = ");
    report_value(line, value, places);
    scriptura_text(line, unit);
    scriptura_character(line, '\n');
}

void report_interval(ScripturaLine *line, const char *name, SimRational low, SimRational high, const char *unit,
                     unsigned int places)
{
    scriptura_text(line, "  ");
    scriptura_text(line, name);
    scriptura_text(line, " between ");
    report_value(line, low, places);
    scriptura_text(line, " and ");
    report_value(line, high, places);
    scriptura_text(line, unit);
    scriptura_character(line, '\n');
}

int report_short(void)
{
    return s_sim_rational_wide != 0;
}
