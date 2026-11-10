import { useState } from "react";
import Lightbox from "yet-another-react-lightbox";
import Zoom from "yet-another-react-lightbox/plugins/zoom";
import Counter from "yet-another-react-lightbox/plugins/counter";
import "yet-another-react-lightbox/styles.css";
import "yet-another-react-lightbox/plugins/counter.css";

type Photo = { src: string; alt?: string };

type Props = {
  photos: Photo[];
  labels: { open: string; close: string; previous: string; next: string; more: string };
};

export function PhotoGallery({ photos, labels }: Props) {
  const [index, setIndex] = useState(-1);
  if (photos.length === 0) return null;

  const thumbs = photos.slice(1, 5);
  const hidden = photos.length - 1 - thumbs.length;

  return (
    <>
      <div className={["grid gap-2", thumbs.length > 0 ? "md:grid-cols-[2fr_1fr]" : ""].join(" ")}>
        <button
          type="button"
          onClick={() => setIndex(0)}
          aria-label={labels.open}
          className="aspect-video overflow-hidden rounded-xl bg-zinc-100 dark:bg-zinc-800"
        >
          <img src={photos[0].src} alt={photos[0].alt ?? ""} className="size-full object-cover transition hover:scale-[1.02]" />
        </button>

        {thumbs.length > 0 && (
          <div className="grid grid-cols-4 gap-2 md:grid-cols-2">
            {thumbs.map((p, i) => (
              <button
                key={p.src}
                type="button"
                onClick={() => setIndex(i + 1)}
                aria-label={labels.open}
                className="relative aspect-square overflow-hidden rounded-lg bg-zinc-100 md:aspect-auto dark:bg-zinc-800"
              >
                <img src={p.src} alt={p.alt ?? ""} loading="lazy" className="size-full object-cover" />
                {i === thumbs.length - 1 && hidden > 0 && (
                  <span className="absolute inset-0 flex items-center justify-center bg-black/50 text-lg font-semibold text-white">
                    {labels.more.replace("%{count}", String(hidden))}
                  </span>
                )}
              </button>
            ))}
          </div>
        )}
      </div>

      <Lightbox
        open={index >= 0}
        index={Math.max(index, 0)}
        close={() => setIndex(-1)}
        slides={photos.map((p) => ({ src: p.src, alt: p.alt }))}
        plugins={[Zoom, Counter]}
        carousel={{ finite: photos.length < 3 }}
        labels={{ Close: labels.close, Previous: labels.previous, Next: labels.next }}
      />
    </>
  );
}
