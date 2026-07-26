unit Atropos.VCL.Main;

interface
uses
  Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ComCtrls, Winapi.Messages, Winapi.Windows, System.SysUtils, System.Classes, System.IOUtils,
  Vcl.Controls, Atropos.Application.AppService, Atropos.Application.Factory, Atropos.Core.Config;

type
  TMainForm = class(TForm)
    LblProject: TLabel;
    EdtProject: TEdit;
    BtnBrowse: TButton;
    BtnRun: TButton;
    ProgressBar1: TProgressBar;
    MemoLog: TMemo;
    OpenDialog1: TOpenDialog;
    GroupBoxOptions: TGroupBox;
    ChkRemove: TCheckBox;
    ChkMove: TCheckBox;
    ChkDebug: TCheckBox;
    procedure BtnBrowseClick(Sender: TObject);
    procedure BtnRunClick(Sender: TObject);
  private
    procedure LogMessage(const AMsg: string);
    procedure UpdateProgress(AMax, APosition: Integer);
    procedure ExecuteProcess(const ADprojPath: string);
  public
    
  end;

var
  MainForm: TMainForm;

implementation

{$R *.dfm}

procedure TMainForm.BtnBrowseClick(Sender: TObject);
begin
  if OpenDialog1.Execute then
    EdtProject.Text := OpenDialog1.FileName;
end;

procedure TMainForm.LogMessage(const AMsg: string);
begin
  TThread.Queue(nil,
    procedure
    begin
      MemoLog.Lines.Add(AMsg);
      SendMessage(MemoLog.Handle, EM_LINESCROLL, 0, MemoLog.Lines.Count);
    end);
end;

procedure TMainForm.UpdateProgress(AMax, APosition: Integer);
begin
  TThread.Queue(nil,
    procedure
    begin
      ProgressBar1.Max := AMax;
      ProgressBar1.Position := APosition;
    end);
end;

procedure TMainForm.ExecuteProcess(const ADprojPath: string);
begin
  TThread.CreateAnonymousThread(
    procedure
    var
      LAppService: TProjectCleanerAppService;
      LConfig: TToolConfig;
    begin
      try
        LConfig := TToolConfig.Default;
        LConfig.RemoveUnused := MainForm.ChkRemove.Checked;
        LConfig.MoveToImplementation := MainForm.ChkMove.Checked;
        LConfig.EnableDebug := MainForm.ChkDebug.Checked;
        
        LAppService := TAppServiceFactory.CreateDefault(LConfig);
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
              BtnRun.Enabled := True;
              BtnBrowse.Enabled := True;
            end);
        end;
      except
        on E: Exception do
        begin
          LogMessage('Critical Error: ' + E.Message);
          TThread.Queue(nil,
            procedure
            begin
              BtnRun.Enabled := True;
              BtnBrowse.Enabled := True;
            end);
        end;
      end;
    end).Start;
end;

procedure TMainForm.BtnRunClick(Sender: TObject);
begin
  if not FileExists(EdtProject.Text) then
  begin
    ShowMessage('Selecione um projeto válido!');
    Exit;
  end;
  
  MemoLog.Clear;
  BtnRun.Enabled := False;
  BtnBrowse.Enabled := False;
  ProgressBar1.Position := 0;
  
  ExecuteProcess(EdtProject.Text);
end;

end.

