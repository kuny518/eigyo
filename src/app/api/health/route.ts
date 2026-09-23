// Cloud Run の起動確認用。認証不要
export function GET() {
  return Response.json({ status: "ok" });
}
