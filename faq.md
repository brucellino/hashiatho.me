---
layout: page
title: FAQ
permalink: /faq/
---

{% include toc.html %}

{% for faq in site.data.faq %}

### {{ faq.q }}

{{ faq.a | markdownify }}

{% endfor %}
