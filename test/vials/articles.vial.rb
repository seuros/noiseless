# frozen_string_literal: true

vial :articles do
  base do
    status "published"
    category "technology"
  end

  variant :intro do
    id 1
    title "Introduction to Search Engines"
    content "Search engines are powerful tools that help users find information quickly and efficiently. This article covers the basics of how search engines work."
    author "John Doe"
    tags %w[search engines tutorial basics]
    published_at 7.days.ago
    view_count 1250
  end

  variant :elasticsearch do
    id 2
    title "Advanced Elasticsearch Techniques"
    content "Elasticsearch is a distributed search and analytics engine. Learn advanced techniques for optimizing your Elasticsearch clusters."
    author "Jane Smith"
    tags %w[elasticsearch search analytics optimization]
    published_at 3.days.ago
    view_count 890
  end

  variant :opensearch do
    id 3
    title "Getting Started with OpenSearch"
    content "OpenSearch is a community-driven, open source search and analytics suite. This guide will help you get started."
    author "Bob Wilson"
    tags %w[opensearch search analytics open-source]
    published_at 5.days.ago
    view_count 654
  end

  variant :typesense do
    id 4
    title "Typesense: Fast Search Made Simple"
    content "Typesense is an open source, typo-tolerant search engine that delivers fast search experiences. Learn how to implement it."
    author "Alice Johnson"
    tags %w[typesense search typo-tolerant fast]
    published_at 1.day.ago
    view_count 432
  end

  variant :draft do
    id 5
    title "Draft Article About Search Performance"
    content "This is a draft article discussing various performance optimization techniques for search systems."
    author "Charlie Brown"
    status "draft"
    tags %w[performance search optimization draft]
    published_at nil
    view_count 0
  end

  variant :rails do
    id 6
    title "Ruby on Rails Search Integration"
    content "Learn how to integrate various search engines with Ruby on Rails applications. Best practices and common patterns."
    author "Diana Prince"
    tags %w[ruby rails search integration]
    published_at 2.days.ago
    view_count 723
    category "programming"
  end

  variant :analytics do
    id 7
    title "Search Analytics and Metrics"
    content "Understanding search analytics is crucial for improving user experience. This article covers key metrics and analysis techniques."
    author "Eve Adams"
    tags %w[analytics metrics search user-experience]
    published_at 4.days.ago
    view_count 567
  end

  variant :javascript do
    id 8
    title "Building Search UIs with Modern JavaScript"
    content "Modern JavaScript frameworks make it easy to build responsive search interfaces. Learn about best practices and common patterns."
    author "Frank Miller"
    tags %w[javascript ui search frontend]
    published_at 6.days.ago
    view_count 834
    category "programming"
  end

  variant :seo do
    id 9
    title "Search Engine Optimization for Developers"
    content "SEO isn't just for marketers. Developers need to understand how to build search-friendly applications."
    author "Grace Lee"
    tags %w[seo search optimization development]
    published_at 8.days.ago
    view_count 1100
    category "development"
  end

  variant :future do
    id 10
    title "Future of Search Technology"
    content "What does the future hold for search technology? This article explores emerging trends and technologies."
    author "Henry Taylor"
    tags %w[future search technology trends]
    published_at 9.days.ago
    view_count 945
  end

  # Generate one of each variant with clean labels
  generate 1, :intro, label_prefix: :intro
  generate 1, :elasticsearch, label_prefix: :elasticsearch
  generate 1, :opensearch, label_prefix: :opensearch
  generate 1, :typesense, label_prefix: :typesense
  generate 1, :draft, label_prefix: :draft
  generate 1, :rails, label_prefix: :rails
  generate 1, :analytics, label_prefix: :analytics
  generate 1, :javascript, label_prefix: :javascript
  generate 1, :seo, label_prefix: :seo
  generate 1, :future, label_prefix: :future
end
