unit Atropos.VCL.Main;

interface

uses
  Vcl.Forms,
  Vcl.Dialogs,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Winapi.Messages,
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Vcl.Controls,
  Atropos.Application.AppService,
  Atropos.Application.ExecutionConfig,
  Atropos.Application.Factory,
  Atropos.Core.Config;

type
  TMainForm = class(TForm)
    ProjectLabel: TLabel;
    ProjectEdit: TEdit;
    BrowseButton: TButton;
    RunButton: TButton;
    ExecutionProgressBar: TProgressBar;
    LogMemo: TMemo;
    ProjectOpenDialog: TOpenDialog;
    OptionsGroupBox: TGroupBox;
    RemoveCheckBox: TCheckBox;
    MoveCheckBox: TCheckBox;
    DebugCheckBox: TCheckBox;
    procedure BrowseButtonClick(Sender: TObject);
    procedure RunButtonClick(Sender: TObject);
  private
    procedure LogMessage(const AMsg: string);
    procedure UpdateProgress(AMax, APosition: Integer);
    procedure ExecuteProcess(const ADprojPath: string; const AConfig: TToolConfig);
  end;

var
  MainForm: TMainForm;

implementation

{$R *.dfm}

procedure TMainForm.BrowseButtonClick(Sender: TObject);
begin
  if ProjectOpenDialog.Execute then
    ProjectEdit.Text := ProjectOpenDialog.FileName;
end;

procedure TMainForm.LogMessage(const AMsg: string);
begin
  TThread.Queue(nil,
    procedure
    begin
      LogMemo.Lines.Add(AMsg);
      SendMessage(LogMemo.Handle, EM_LINESCROLL, 0, LogMemo.Lines.Count);
    end);
end;

procedure TMainForm.UpdateProgress(AMax, APosition: Integer);
begin
  TThread.Queue(nil,
    procedure
    begin
      ExecutionProgressBar.Max := AMax;
      ExecutionProgressBar.Position := APosition;
    end);
end;

procedure TMainForm.ExecuteProcess(const ADprojPath: string; const AConfig: TToolConfig);
begin
  TThread.CreateAnonymousThread(
    procedure
    var
      LAppService: TProjectCleanerAppService;
    begin
      try
        LAppService := TAppServiceFactory.CreateDefault(AConfig);
        try
          LAppService.OnLog := procedure(const AMsg: string)
            begin
              LogMessage(AMsg);
            end;
          
          LAppService.OnProgress := procedure(AMax, APosition: Integer)
            begin
              UpdateProgress(AMax, APosition);
            end;
          
          LAppService.Execute(ADprojPath);
          
        finally
          LAppService.Free;
          
          TThread.Queue(nil,
            procedure
            begin
              RunButton.Enabled := True;
              BrowseButton.Enabled := True;
            end);
        end;
      except
        on E: Exception do
        begin
          LogMessage('Critical Error: ' + E.Message);
          TThread.Queue(nil,
            procedure
            begin
              RunButton.Enabled := True;
              BrowseButton.Enabled := True;
            end);
        end;
      end;
    end).Start;
end;

procedure TMainForm.RunButtonClick(Sender: TObject);
var
  LConfig: TToolConfig;
begin
  if not FileExists(ProjectEdit.Text) then
  begin
    ShowMessage('Selecione um projeto válido!');
    Exit;
  end;
  
  LogMemo.Clear;
  RunButton.Enabled := False;
  BrowseButton.Enabled := False;
  ExecutionProgressBar.Position := 0;
  
  LConfig := TExecutionConfigFactory.FromSelections(
    RemoveCheckBox.Checked,
    MoveCheckBox.Checked,
    DebugCheckBox.Checked);
  ExecuteProcess(ProjectEdit.Text, LConfig);
end;

end.
