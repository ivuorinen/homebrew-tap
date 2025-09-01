---
layout: default
title: Home
---

# ivuorinen/homebrew-tap

Welcome to the documentation for ivuorinen's Homebrew tap. This tap contains custom formulae for various tools and utilities.

## Quick Start

```bash
brew tap ivuorinen/homebrew-tap
brew install <formula-name>
```

## Available Formulae

{% if site.data.formulae.formulae.size > 0 %}
<div class="formulae-grid">
{% for formula in site.data.formulae.formulae %}
  <div class="formula-card">
    <h3><a href="{{ '/formula/' | append: formula.name | relative_url }}">{{ formula.name }}</a></h3>
    {% if formula.description %}<p>{{ formula.description }}</p>{% endif %}
    <div class="formula-meta">
      {% if formula.version %}<span class="version">v{{ formula.version }}</span>{% endif %}
      {% if formula.license %}<span class="license">{{ formula.license }}</span>{% endif %}
    </div>
  </div>
{% endfor %}
</div>
{% else %}
<p>No formulae available yet. Add some formulae to the <code>Formula/</code> directory to get started.</p>
{% endif %}

## Repository

View the source code and contribute on [GitHub](https://github.com/{{ site.repository }}).

---

*Documentation automatically generated from formula files.*
