unit Rollback.Main;

interface

procedure Run;

implementation

uses
  System.SysUtils,
  Rollback.Unused;

procedure Run;
begin
  Writeln('rollback fixture');
end;

end.
