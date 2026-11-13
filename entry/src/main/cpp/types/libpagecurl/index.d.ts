import { image } from '@kit.ImageKit';
export const cache: (id: string,key: string,map: image.PixelMap) => Promise<boolean>;
export const retain: (id: string,keys: string) => boolean;
export const prioritize: (id: string,keys: string) => boolean;
export const clear: (id: string) => boolean;
export const presented: (id: string,sequence: number) => boolean;
export const present: (id: string,front: string,behind: string,progress: number,corner: number,fingerY: number,reverse: number,book: number,velocity: number,margin: number) => number;
export const metrics: (id: string) => string;
