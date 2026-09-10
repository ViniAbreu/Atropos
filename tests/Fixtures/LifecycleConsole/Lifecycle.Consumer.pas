unit Lifecycle.Consumer;
interface
uses Lifecycle.Provider, Lifecycle.Unused, Lifecycle.Bridge;
implementation
initialization
  Boot;
finalization
  Shutdown;
end.