# frozen_string_literal: true

# Abstract base class for all search models
class ApplicationSearch < Noiseless::Model
  # Mark as abstract - concrete search models like Product::Search inherit from this
  def self.abstract!
    @abstract = true
  end

  def self.abstract?
    @abstract == true
  end

  abstract!
end
