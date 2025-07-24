defmodule SampleApp.CommandedApp do
  @moduledoc """
  The main Commanded application for the sample app.
  
  This module defines the Commanded application that will use the ExESDB
  adapter for event storage. It's configured to use the ExESDB cluster
  and includes all the necessary components for CQRS/ES operations.
  """
  use Commanded.Application, otp_app: :sample_app

  # Configure the router (will be created as needed)
  router(SampleApp.Router)

  # Event handlers (projections) and policies are automatically registered
  # when they use Commanded.Event.Handler with application: SampleApp.CommandedApp
  
  # Configure middleware (optional, can be added later)
  # middleware([
  #   SampleApp.Middleware.Logger,
  #   Commanded.Middleware.Uniqueness,
  #   Commanded.Middleware.Validate
  # ])
end
