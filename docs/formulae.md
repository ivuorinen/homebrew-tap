---
layout: default
title: All Formulae
---

# All Formulae

{% if site.data.formulae.formulae.size > 0 %}
{% for formula in site.data.formulae.formulae %}
## [{{ formula.name }}]({{ '/formula/' | append: formula.name | relative_url }})

{% if formula.description %}{{ formula.description }}{% endif %}

**Installation:**
```bash
brew install {{ formula.name }}
```

{% if formula.dependencies.size > 0 %}
**Dependencies:** {{ formula.dependencies | join: ', ' }}
{% endif %}

---
{% endfor %}
{% else %}
No formulae available yet. Add some formulae to the `Formula/` directory to get started.
{% endif %}
