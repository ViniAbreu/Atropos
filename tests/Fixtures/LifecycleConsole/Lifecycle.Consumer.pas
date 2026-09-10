unit Lifecycle.Consumer;
interface
uses Lifecycle.Provider, Lifecycle.Unused;
implementation
initialization
  Boot;
finalization
  Shutdown;
end.