// Shared AI narration endpoint used by every module's AiInsightCard.
// Holds the Gemini key server-side; the client only ever sends numbers/text
// and receives a plain-language string back. See the "Shared AI service"
// section of the README for the full design.

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// "gemini-1.5-flash" was retired since the plan was written. Using the
// "-latest" alias instead of a pinned version so this doesn't need a
// redeploy every time Google rotates the flash-tier model underneath it.
const GEMINI_MODEL = "gemini-flash-latest";

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // Supabase's platform-level JWT verification (config.toml verify_jwt = true)
  // already rejects anonymous calls before this runs. This check is a
  // defensive second layer, not the only gate.
  const auth = req.headers.get("Authorization");
  if (!auth) {
    return new Response(JSON.stringify({ error: "unauthorized" }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  let prompt: string;
  let system: string | undefined;
  try {
    const body = await req.json();
    prompt = body?.prompt;
    system = body?.system;
    if (typeof prompt !== "string" || prompt.trim() === "") {
      throw new Error("missing prompt");
    }
  } catch {
    return new Response(JSON.stringify({ error: "invalid request body" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const key = Deno.env.get("GEMINI_API_KEY");
  if (!key) {
    return new Response(
      JSON.stringify({ error: "GEMINI_API_KEY not configured" }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

  try {
    const resp = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${key}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contents: [
            { parts: [{ text: (system ? system + "\n\n" : "") + prompt }] },
          ],
        }),
      },
    );

    if (!resp.ok) {
      const errText = await resp.text();
      return new Response(
        JSON.stringify({ error: `Gemini API error: ${errText}` }),
        {
          status: 502,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const data = await resp.json();
    const text = data?.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
    return new Response(JSON.stringify({ text }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
