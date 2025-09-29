import type { NextApiRequest, NextApiResponse } from "next";

export default function handler(req: NextApiRequest, res: NextApiResponse) {
  const { slug } = req.query;
  const path = Array.isArray(slug) ? slug.join("/") : slug;
  const blobUrl = `https://nt9pzjxsvf6ahuq3.public.blob.vercel-storage.com/${path}`;
  res.redirect(blobUrl);
}
